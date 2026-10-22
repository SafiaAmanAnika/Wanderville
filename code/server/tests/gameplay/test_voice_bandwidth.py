"""How much the voice path really costs, in bytes, per listener.

The numbers here are the bytes the server actually sends: the length of the
WebSocket messages a listener receives, not an estimate. They are measured in
the three situations that matter in a small room, with nobody speaking, with
one person speaking, and with everybody speaking. The raw PCM path and the
Opus path are measured the same way, because the point of the comparison is
the difference between them.

Every client in the room is measured, not only the one that is listened to.
The server mixes the room for each peer, so the room costs the server one
stream per client, and the total egress of a room is the sum of them.
"""
import json
import math
import os
import queue
import struct
import threading
import time
from contextlib import ExitStack

import pytest

from app.core.config import settings
from app.modules.realtime.opus import OPUS_MARKER

from test_native_voice_opus import command, connect, decode, decoder

## How long the window with people talking lasts.
TALKING_WINDOW = 2.0

## How long the window with a quiet room lasts.
QUIET_WINDOW = 2.0

## How long the window with nobody in the room lasts. It is longer than the
## keepalive interval on purpose: a quiet room costs a keepalive, and a
## keepalive only shows up once per interval.
IDLE_WINDOW = 7.0

## How often a speaker sends a frame. The server mixes a room every 20 ms, so
## the speaker has to be quicker than that or a tick finds the room empty and
## calls it silent. It is not a rate a real client would use: the timer on
## Windows has a resolution of about 16 ms, so a 10 ms wait is really a
## 16 ms wait, and the speaker ends up comfortably ahead of the mixer.
SEND_INTERVAL = 0.01

## How long the room is given to settle between two measurements. A socket
## that closes is torn down on the server a moment later, and that teardown
## expires the presence of the player. Reconnecting the same player in the
## same breath would race with it, so the benchmark waits for the dust to
## settle instead of measuring a race.
SETTLE_SECONDS = 1.0

## How often a control socket is heartbeated. The server only keeps a voice
## lease alive for two seconds, so a longer gap would end the stream.
HEARTBEAT_INTERVAL = 0.4

## The tone the speakers send, and what it has to sound like on the way out.
TONE_FREQUENCY = 440.0
TONE_AMPLITUDE = 8000

## What one frame of audio costs on the wire as raw PCM.
PCM_FRAME_BYTES = 1920

## The number of frames the server mixes in a second.
FRAMES_PER_SECOND = 50


def tone_frame(amplitude=TONE_AMPLITUDE, frequency=TONE_FREQUENCY):
    """One 20 ms mono frame of a tone, as the client would send it."""
    return b"".join(
        struct.pack(
            "<h", int(amplitude * math.sin(2 * math.pi * frequency * i / 48000))
        )
        for i in range(960)
    )


def websocket_frame_bytes(payload_size):
    """What a payload costs on the wire, headers and all.

    A frame from the server to a client is not masked, so the overhead is the
    two byte header plus the extended length field for a payload that does
    not fit in the single length byte.
    """
    if payload_size < 126:
        return payload_size + 2
    if payload_size < 65536:
        return payload_size + 4
    return payload_size + 10


def window_wire_bytes(window):
    """What a window cost on the wire, payload and framing together."""
    audio = sum(websocket_frame_bytes(size) for size in window["frame_sizes"])
    text = sum(websocket_frame_bytes(size) for size in window["text_sizes"])
    return audio + text


def gaps(arrivals):
    """The pauses between the frames that arrived, in milliseconds."""
    ordered = sorted(arrivals)
    return [
        (later - earlier) * 1000 for earlier, later in zip(ordered, ordered[1:])
    ]


class Heartbeat:
    """Keeps a control lease alive while a measurement runs.

    The server stops publishing to a peer two seconds after the last control
    message, so a benchmark that measures for longer than that has to keep
    the lease warm.
    """

    def __init__(self, socket, interval=HEARTBEAT_INTERVAL):
        self.socket = socket
        self.interval = interval
        self.stopped = threading.Event()
        self.sent = 0
        self.errors = []
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        counter = 0
        while not self.stopped.wait(self.interval):
            counter += 1
            try:
                self.socket.send_json(
                    {
                        "type": "heartbeat",
                        "data": {},
                        "request_id": f"bench_{counter}",
                    }
                )
                self.sent += 1
            except Exception as error:  # pragma: no cover - a broken socket
                self.errors.append(repr(error))
                return

    def stop(self):
        self.stopped.set()


class Speaker:
    """Sends a tone into the room, for as long as it is left running."""

    def __init__(self, socket, frame=None, interval=SEND_INTERVAL):
        self.socket = socket
        self.frame = frame or tone_frame()
        self.interval = interval
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        while not self.stopped.wait(self.interval):
            try:
                self.socket.send_bytes(self.frame)
            except Exception:
                return

    def stop(self):
        self.stopped.set()


class Reader:
    """Drains an audio socket in the background and counts what arrives.

    The measurement then never blocks on a socket that has nothing to say,
    which is the whole point of a benchmark that has to also work in a quiet
    room. It counts the audio, the keepalives and the arrival times, because
    the arrival times are what say whether the audio stuttered.
    """

    def __init__(self, socket):
        self.socket = socket
        self.lock = threading.Lock()
        self.audio_bytes = 0
        self.audio_frames = 0
        self.audio_arrivals = []
        self.audio_sizes = []
        self.audio_payloads = []
        self.text_bytes = 0
        self.text_frames = 0
        self.text_sizes = []
        self.total_text_bytes = 0
        self.total_text_frames = 0
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        try:
            while True:
                message = self.socket.receive()
                arrived = time.monotonic()
                with self.lock:
                    payload = message.get("bytes")
                    if payload is not None:
                        self.audio_bytes += len(payload)
                        self.audio_frames += 1
                        self.audio_arrivals.append(arrived)
                        self.audio_sizes.append(len(payload))
                        self.audio_payloads.append(payload)
                    else:
                        text = message.get("text")
                        if text is not None:
                            size = len(text.encode())
                            self.text_bytes += size
                            self.text_frames += 1
                            self.text_sizes.append(size)
                            self.total_text_bytes += size
                            self.total_text_frames += 1
        except Exception:
            return

    def measure(self, seconds):
        """What arrived in the next window."""
        with self.lock:
            self.audio_bytes = 0
            self.audio_frames = 0
            self.text_bytes = 0
            self.text_frames = 0
            self.audio_arrivals = []
            self.audio_sizes = []
            self.audio_payloads = []
            self.text_sizes = []
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            time.sleep(0.01)
        with self.lock:
            window = {
                "audio_bytes": self.audio_bytes,
                "audio_frames": self.audio_frames,
                "text_bytes": self.text_bytes,
                "text_frames": self.text_frames,
                "arrivals": list(self.audio_arrivals),
                "frame_sizes": list(self.audio_sizes),
                "payloads": list(self.audio_payloads),
                "text_sizes": list(self.text_sizes),
                "total_text_bytes": self.total_text_bytes,
                "total_text_frames": self.total_text_frames,
            }
        window["wire_bytes"] = window_wire_bytes(window)
        return window


def be_friends(client, listener, speakers):
    """Make the listener and the speakers a circle of friends."""
    for speaker in speakers:
        assert (
            client.post(
                "/social/requests", headers=listener.headers, json={"target_id": speaker.id}
            ).status_code
            == 200
        )
        assert (
            client.post(
                f"/social/friends/{listener.id}",
                headers=speaker.headers,
                json={"action": "accept"},
            ).status_code
            == 200
        )


def measure_room(stack, client, label, capabilities, listener, speakers):
    """Measure what one room costs, with a given number of speakers.

    The room is measured twice: with the speakers talking, and with the room
    quiet again. The quiet window is where the keepalive shows up.
    """
    control, audio, session_id, negotiated = connect(
        stack, client, listener, capabilities=capabilities
    )
    # A peer is muted until it says otherwise, so the room has to be told.
    command(control, "voice.state", {"session_id": session_id, "muted": False})
    heartbeats = [Heartbeat(control)]
    readers = [Reader(audio)]
    speaker_sockets = []
    for speaker in speakers:
        speaker_control, speaker_audio, speaker_session, _ = connect(
            stack, client, speaker, capabilities=capabilities
        )
        command(
            speaker_control,
            "voice.state",
            {"session_id": speaker_session, "muted": False},
        )
        heartbeats.append(Heartbeat(speaker_control))
        readers.append(Reader(speaker_audio))
        speaker_sockets.append(speaker_audio)

    try:
        # Let the room fill up before anything is counted.
        time.sleep(0.5)
        started = time.monotonic()
        if speaker_sockets:
            loud = [Speaker(socket) for socket in speaker_sockets]
            try:
                # Let the talkers reach the mixer before the window opens, so
                # the window is the steady state and not the first frames.
                time.sleep(0.5)
                talking = [reader.measure(TALKING_WINDOW) for reader in readers]
            finally:
                for speaker in loud:
                    speaker.stop()
            # Let the last frames age out of the mixer.
            time.sleep(0.5)
            quiet = [reader.measure(QUIET_WINDOW) for reader in readers]
        else:
            talking = [reader.measure(TALKING_WINDOW) for reader in readers]
            quiet = [reader.measure(IDLE_WINDOW) for reader in readers]
        elapsed = time.monotonic() - started
    finally:
        for heartbeat in heartbeats:
            heartbeat.stop()

    listener_window = talking[0]
    listener_gaps = gaps(listener_window["arrivals"])
    per_frame = 0
    if listener_window["audio_frames"]:
        per_frame = listener_window["wire_bytes"] / listener_window["audio_frames"]
    return {
        "key": f"{label}_{len(speakers)}",
        "path": label,
        "encoding": negotiated["encoding"],
        "speakers": len(speakers),
        "clients": len(readers),
        "talking_frames": listener_window["audio_frames"],
        "talking_audio_bytes": listener_window["audio_bytes"],
        "talking_wire_bytes": listener_window["wire_bytes"],
        "talking_wire_bytes_per_frame": round(per_frame, 1),
        # The mixer sends a frame every 20 ms. A window does not always hold
        # all of them, because the load generator and the server share one
        # process, so the steady rate is the cost of a frame times the rate the
        # mixer really runs at.
        "talking_steady_bytes_per_second": int(per_frame * FRAMES_PER_SECOND),
        "talking_bytes_per_second": int(listener_window["wire_bytes"] / TALKING_WINDOW),
        "talking_kbit_per_second": int(
            listener_window["wire_bytes"] * 8 / TALKING_WINDOW / 1000
        ),
        "talking_mean_gap_ms": round(sum(listener_gaps) / len(listener_gaps), 1)
        if listener_gaps
        else 0.0,
        "talking_max_gap_ms": round(max(listener_gaps), 1) if listener_gaps else 0.0,
        "quiet_audio_bytes": sum(window["audio_bytes"] for window in quiet),
        "quiet_wire_bytes": sum(window["wire_bytes"] for window in quiet),
        "keepalive_frames": sum(
            reader.total_text_frames for reader in readers
        ),
        "keepalive_bytes": sum(reader.total_text_bytes for reader in readers),
        "keepalive_bytes_per_second": int(
            sum(reader.total_text_bytes for reader in readers) / elapsed
        ),
        "room_egress_bytes_per_second": int(
            sum(window["wire_bytes"] for window in talking) / TALKING_WINDOW
        ),
        "heartbeats_sent": sum(heartbeat.sent for heartbeat in heartbeats),
        "heartbeat_errors": [error for heartbeat in heartbeats for error in heartbeat.errors],
    }


def test_voice_bandwidth(client, account, monkeypatch, capsys):
    """The bytes a listener pays for, in every situation that matters."""
    monkeypatch.setattr(settings, "voice_enabled", True)
    report = []
    failures = []

    # Signup is rate limited to five a minute, so the same people sit in every
    # room instead of a fresh set for each measurement.
    listener = account("bench_listener")
    speakers = [account(f"bench_speaker_{index}") for index in range(4)]
    be_friends(client, listener, speakers)

    for label, capabilities in (
        ("pcm", ["silence_suppression"]),
        ("opus", ["silence_suppression", "opus"]),
    ):
        for speaker_count in (0, 1, 4):
            key = f"{label}_{speaker_count}"
            with ExitStack() as stack:
                try:
                    report.append(
                        measure_room(
                            stack,
                            client,
                            label,
                            capabilities,
                            listener,
                            speakers[:speaker_count],
                        )
                    )
                except Exception as error:
                    # A scenario that failed is reported as failed. It is never
                    # filled in with a number nobody measured.
                    failures.append({"key": key, "error": repr(error)})
            # Let the server finish tearing the room down before the next
            # measurement moves the same people into another room.
            time.sleep(SETTLE_SECONDS)

    with capsys.disabled():
        print()
        print("voice bandwidth: what one client receives, and what the room costs")
        print(
            f"{'scenario':<10}{'encoding':>10}{'clients':>8}{'frames':>8}"
            f"{'B/frame':>9}{'B/s':>10}{'kbit/s':>9}{'mean gap ms':>13}"
            f"{'keepalive B/s':>14}{'room B/s':>10}"
        )
        for row in report:
            print(
                f"{row['key']:<10}{row['encoding']:>10}{row['clients']:>8}"
                f"{row['talking_frames']:>8}"
                f"{row['talking_wire_bytes_per_frame']:>9.1f}"
                f"{row['talking_bytes_per_second']:>10}"
                f"{row['talking_kbit_per_second']:>9}{row['talking_mean_gap_ms']:>13}"
                f"{row['keepalive_bytes_per_second']:>14}"
                f"{row['room_egress_bytes_per_second']:>10}"
            )
        print()

    destination = os.environ.get("VOICE_BENCH_REPORT")
    if destination:
        with open(destination, "w", encoding="utf-8") as handle:
            json.dump({"scenarios": report, "failures": failures}, handle, indent=2)

    if failures:
        pytest.fail(f"scenarios failed: {failures}")

    rows = {row["key"]: row for row in report}
    expected = FRAMES_PER_SECOND * TALKING_WINDOW
    for path in ("pcm", "opus"):
        # A room with nobody in it costs nothing but the keepalive.
        assert rows[f"{path}_0"]["talking_audio_bytes"] == 0
        # A room where nobody talks costs nothing but the keepalive.
        assert rows[f"{path}_1"]["quiet_audio_bytes"] == 0
        assert rows[f"{path}_4"]["quiet_audio_bytes"] == 0
        # Somebody talking costs something.
        assert rows[f"{path}_1"]["talking_audio_bytes"] > 0
        assert rows[f"{path}_4"]["talking_audio_bytes"] > 0
        # The frames arrive at the rate the mixer works at.
        assert rows[f"{path}_1"]["talking_mean_gap_ms"] == pytest.approx(20, abs=3)
        assert rows[f"{path}_4"]["talking_mean_gap_ms"] == pytest.approx(20, abs=3)
        # A floor on the frames, not an exact count: the load generator and the
        # server share one process here, so a busy machine costs both of them
        # a few frames in a window. The cadence above is what says whether the
        # audio stuttered.
        assert rows[f"{path}_1"]["talking_frames"] >= expected * 0.85
        assert rows[f"{path}_4"]["talking_frames"] >= expected * 0.85
        # A frame is worth what it is worth: a raw frame is 1,920 bytes of
        # audio plus its header, a compressed one is a fraction of that.
        assert rows[f"{path}_1"]["talking_wire_bytes_per_frame"] == pytest.approx(
            1924 if path == "pcm" else 63, rel=0.1
        )

    # The same room, the same talker, a fraction of the bytes.
    pcm = rows["pcm_1"]["talking_steady_bytes_per_second"]
    opus = rows["opus_1"]["talking_steady_bytes_per_second"]
    assert opus < pcm / 4, (pcm, opus)
    # Opus is worth about 24 kbit/s, plus the framing around it.
    assert 1500 <= opus <= 6000, opus
    # Compression must not cost frames.
    assert rows["opus_1"]["talking_frames"] >= rows["pcm_1"]["talking_frames"] * 0.9
    assert rows["opus_4"]["talking_frames"] >= rows["pcm_4"]["talking_frames"] * 0.9


@pytest.mark.parametrize("path", ["pcm", "opus"])
def test_voice_bandwidth_stays_quiet_when_nobody_speaks(
    client, account, monkeypatch, path
):
    """A quiet room must cost nothing on the wire, in either encoding."""
    monkeypatch.setattr(settings, "voice_enabled", True)
    listener = account(f"quiet_{path}")
    be_friends(client, listener, [])
    with ExitStack() as stack:
        control, audio, _session, _negotiated = connect(
            stack,
            client,
            listener,
            capabilities=["silence_suppression"] + (["opus"] if path == "opus" else []),
        )
        heartbeat = Heartbeat(control)
        reader = Reader(audio)
        try:
            window = reader.measure(1.0)
        finally:
            heartbeat.stop()
    assert (
        window["audio_bytes"] == 0
    ), f"a quiet room sent {window['audio_bytes']} bytes"


def zero_crossings(samples):
    """How often the signal crosses zero, which is what gives a tone its pitch."""
    crossings = 0
    for earlier, later in zip(samples, samples[1:]):
        if (earlier < 0) != (later < 0):
            crossings += 1
    return crossings


def measure_sound(client, account, path, monkeypatch, name):
    """Listen to a room and say what came out of it."""
    monkeypatch.setattr(settings, "voice_enabled", True)
    listener = account(f"{name}_listener")
    speaker = account(f"{name}_speaker")
    be_friends(client, listener, [speaker])
    capabilities = ["silence_suppression"] + (["opus"] if path == "opus" else [])
    with ExitStack() as stack:
        control, audio, session_id, negotiated = connect(
            stack, client, listener, capabilities=capabilities
        )
        command(control, "voice.state", {"session_id": session_id, "muted": False})
        speaker_control, speaker_audio, speaker_session, _ = connect(
            stack, client, speaker, capabilities=capabilities
        )
        command(
            speaker_control,
            "voice.state",
            {"session_id": speaker_session, "muted": False},
        )
        heartbeat = Heartbeat(control)
        speaker_heartbeat = Heartbeat(speaker_control)
        reader = Reader(audio)
        talker = Speaker(speaker_audio)
        try:
            time.sleep(0.5)
            window = reader.measure(1.5)
        finally:
            talker.stop()
            heartbeat.stop()
            speaker_heartbeat.stop()

    payloads = window["payloads"]
    assert payloads, "nothing was heard"
    if path == "opus":
        context = decoder()
        samples = []
        for payload in payloads:
            assert payload[0] == OPUS_MARKER
            samples.extend(decode(context, payload[1:]))
    else:
        samples = []
        for payload in payloads:
            assert len(payload) == PCM_FRAME_BYTES
            samples.extend(struct.unpack("<960h", payload))
    seconds = len(samples) / 48000
    return {
        "path": path,
        "frames": len(payloads),
        "samples": len(samples),
        "seconds": seconds,
        "peak": max(abs(value) for value in samples),
        "rms": (sum(value * value for value in samples) / len(samples)) ** 0.5,
        "crossings": zero_crossings(samples),
        "crossings_per_second": zero_crossings(samples) / seconds,
    }


def test_compression_keeps_the_sound_intact(client, account, monkeypatch, capsys):
    """The tone that goes in has to come out, in either encoding.

    Compression is allowed to change the sound a little. It is not allowed to
    change the pitch, to make the room quiet, to make it stutter, or to make
    it late.
    """
    pcm = measure_sound(client, account, "pcm", monkeypatch, "sound_pcm")
    opus = measure_sound(client, account, "opus", monkeypatch, "sound_opus")

    with capsys.disabled():
        print()
        print("voice sound: what came out of the room")
        print(
            f"{'path':<6}{'frames':>8}{'samples':>10}{'seconds':>10}"
            f"{'peak':>8}{'rms':>8}{'crossings/s':>14}"
        )
        for row in (pcm, opus):
            print(
                f"{row['path']:<6}{row['frames']:>8}{row['samples']:>10}"
                f"{row['seconds']:>10.2f}{row['peak']:>8}{row['rms']:>8.0f}"
                f"{row['crossings_per_second']:>14.0f}"
            )
        print()

    for row in (pcm, opus):
        # The room is not quiet.
        assert row["peak"] > 2000, row
        # The pitch is the pitch: a 440 Hz tone crosses zero 880 times a second.
        assert row["crossings_per_second"] == pytest.approx(880, rel=0.05), row
        # Nothing stuttered: every frame arrived and every frame was 20 ms.
        assert row["frames"] >= 70, row
        assert row["samples"] == row["frames"] * 960, row

    # The compressed room sounds like the uncompressed one. The pitch is
    # exactly the pitch, and the level is close: a codec is allowed to soften
    # a tone a little, and libopus overshoots the peak of a pure tone.
    assert opus["rms"] == pytest.approx(pcm["rms"], rel=0.25), (pcm, opus)
    assert opus["peak"] == pytest.approx(pcm["peak"], rel=0.35), (pcm, opus)
