"""Opus encoding on the native voice path, and the negotiation around it."""
import math
import struct
import time
from contextlib import ExitStack

import av
import pytest

from app.core.config import settings
from app.modules.realtime.native_voice import OpusUnavailable
from app.modules.realtime.opus import FRAME_BYTES, OPUS_MARKER, OpusEncoder


def command(ws, kind, data=None):
    request_id = "native_" + str(time.monotonic_ns())
    ws.send_json({"type": kind, "data": data or {}, "request_id": request_id})
    for _ in range(50):
        response = ws.receive_json()
        if response.get("request_id") == request_id:
            assert response["type"] != "error", response
            return response
    pytest.fail("No correlated acknowledgement")


def tone_frame(amplitude=12000, frequency=440.0):
    """One 20 ms mono frame of a tone, as the client would send it."""
    return b"".join(
        struct.pack(
            "<h", int(amplitude * math.sin(2 * math.pi * frequency * i / 48000))
        )
        for i in range(960)
    )


def decoder():
    """An Opus decoder, so a test can hear what the server encoded."""
    context = av.CodecContext.create("libopus", "r")
    context.open()
    return context


def decode(context, payload):
    """Decode one Opus frame into little-endian PCM16 samples.

    A frame can come back with two channels, because Opus lets the encoder
    choose the channel count frame by frame, so the channels are mixed down
    to the one channel the voice path uses.
    """
    samples = []
    for frame in context.decode(av.Packet(payload)):
        channels = frame.layout.nb_channels
        data = bytes(frame.planes[0])[: frame.samples * channels * 2]
        values = struct.unpack(f"<{frame.samples * channels}h", data)
        if channels == 2:
            samples.extend(
                (left + right) // 2 for left, right in zip(values[0::2], values[1::2])
            )
        else:
            samples.extend(values)
    return samples


def connect(stack, client, user, capabilities=None):
    """Join voice and return the control socket, the audio socket and the
    format the server negotiated."""
    ws = stack.enter_context(client.websocket_connect("/realtime/ws"))
    ws.send_json({"type": "auth", "protocol_version": 2, "token": user.tokens["access_token"]})
    initial = ws.receive_json()
    request_id = "native_" + str(time.monotonic_ns())
    ws.send_json({"type": "voice.join", "data": {"transport": "pcm-websocket"}, "request_id": request_id})
    for _ in range(50):
        response = ws.receive_json()
        if response.get("request_id") == request_id:
            joined = response
            break
    else:
        pytest.fail("The server did not answer voice.join")
    assert joined.get("type") != "error", joined
    sid = joined["data"]["voice"]["session_id"]
    audio = stack.enter_context(client.websocket_connect("/realtime/voice/ws"))
    auth = {
        "type": "auth",
        "token": user.tokens["access_token"],
        "connection_id": initial["connection_id"],
        "session_id": sid,
    }
    if capabilities:
        auth["capabilities"] = list(capabilities)
    audio.send_json(auth)
    negotiated = None
    for _ in range(4):
        message = audio.receive_json()
        if message["type"] == "voice.format":
            negotiated = message
            continue
        assert message["type"] == "voice.connected"
        break
    return ws, audio, sid, negotiated


def receive_audio(ws, limit=40):
    """The next audio packet, stepping over keepalive messages."""
    for _ in range(limit):
        message = ws.receive()
        if message.get("bytes") is not None:
            return message["bytes"]
    pytest.fail("No audio packet arrived")


def test_opus_encoder_holds_the_target_bitrate():
    """20 ms of audio must cost about 60 bytes, not 1,920."""
    encoder = OpusEncoder(bitrate=24000)
    sizes = []
    for _ in range(50):
        sizes.extend(len(frame) for frame in encoder.encode(tone_frame()))
    average = sum(sizes) / len(sizes)
    assert 40 <= average <= 90, sizes
    assert average * 8 * 50 / 1000 == pytest.approx(24, abs=6)


def test_opus_frames_decode_back_to_the_audio_that_went_in():
    encoder = OpusEncoder(bitrate=24000)
    context = decoder()
    heard = []
    for _ in range(10):
        for frame in encoder.encode(tone_frame()):
            heard.extend(decode(context, frame))
    assert heard
    assert max(abs(value) for value in heard) > 8000


def test_native_opus_is_negotiated_for_a_client_that_asks_for_it(client, account, monkeypatch):
    """A client that declares Opus is told so, and is sent compressed audio."""
    monkeypatch.setattr(settings, "voice_enabled", True)
    monkeypatch.setattr(settings, "voice_opus_enabled", True)
    a, b = account("opus_a"), account("opus_b")
    assert client.post("/social/requests", headers=a.headers, json={"target_id": b.id}).status_code == 200
    assert client.post(f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}).status_code == 200
    with ExitStack() as stack:
        wa, aa, sa, _ = connect(stack, client, a)
        wb, ab, sb, negotiated = connect(
            stack, client, b, capabilities=["silence_suppression", "opus"]
        )
        assert negotiated["encoding"] == "opus"
        assert negotiated["sample_rate"] == 48000
        assert negotiated["frame_samples"] == 960
        assert negotiated["bitrate"] == settings.voice_opus_bitrate
        command(wa, "voice.state", {"session_id": sa, "muted": False})
        command(wb, "heartbeat")
        context = decoder()
        heard = []
        for _ in range(12):
            aa.send_bytes(tone_frame())
            packet = receive_audio(ab)
            assert packet[0] == OPUS_MARKER
            payload = packet[1:]
            assert len(payload) < 200, len(payload)
            heard.extend(decode(context, payload))
            time.sleep(0.02)
        assert max(abs(value) for value in heard) > 4000


def test_native_pcm_is_kept_for_a_client_that_does_not_ask_for_opus(client, account, monkeypatch):
    """The old path is untouched for a client that never heard of Opus."""
    monkeypatch.setattr(settings, "voice_enabled", True)
    a, b = account("pcm_a"), account("pcm_b")
    assert client.post("/social/requests", headers=a.headers, json={"target_id": b.id}).status_code == 200
    assert client.post(f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}).status_code == 200
    with ExitStack() as stack:
        wa, aa, sa, _ = connect(stack, client, a)
        wb, ab, sb, negotiated = connect(stack, client, b, capabilities=["silence_suppression"])
        assert negotiated["encoding"] == "pcm_s16le"
        assert negotiated["bitrate"] is None
        command(wa, "voice.state", {"session_id": sa, "muted": False})
        command(wb, "heartbeat")
        for _ in range(6):
            aa.send_bytes(tone_frame())
            packet = receive_audio(ab)
            assert len(packet) == FRAME_BYTES
            time.sleep(0.02)


def test_native_falls_back_to_pcm_when_the_host_cannot_encode_opus(client, account, monkeypatch):
    """A host without libopus keeps working instead of failing the join."""
    monkeypatch.setattr(settings, "voice_enabled", True)

    def unavailable(*args, **kwargs):
        raise OpusUnavailable("no libopus here")

    monkeypatch.setattr("app.modules.realtime.native_voice.OpusEncoder", unavailable)
    a, b = account("fallback_a"), account("fallback_b")
    assert client.post("/social/requests", headers=a.headers, json={"target_id": b.id}).status_code == 200
    assert client.post(f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}).status_code == 200
    with ExitStack() as stack:
        wa, aa, sa, _ = connect(stack, client, a)
        wb, ab, sb, negotiated = connect(
            stack, client, b, capabilities=["silence_suppression", "opus"]
        )
        assert negotiated["encoding"] == "pcm_s16le"
        command(wa, "voice.state", {"session_id": sa, "muted": False})
        command(wb, "heartbeat")
        for _ in range(6):
            aa.send_bytes(tone_frame())
            packet = receive_audio(ab)
            assert len(packet) == FRAME_BYTES
            time.sleep(0.02)


def test_opus_keeps_the_silence_suppression_and_the_keepalive(client, account, monkeypatch):
    """A quiet room costs nothing whichever encoding is in use."""
    monkeypatch.setattr(settings, "voice_enabled", True)
    monkeypatch.setattr(settings, "voice_idle_keepalive_seconds", 0.2)
    a, b = account("quiet_opus_a"), account("quiet_opus_b")
    assert client.post("/social/requests", headers=a.headers, json={"target_id": b.id}).status_code == 200
    assert client.post(f"/social/friends/{a.id}", headers=b.headers, json={"action": "accept"}).status_code == 200
    with ExitStack() as stack:
        wa, aa, sa, _ = connect(stack, client, a)
        wb, ab, sb, negotiated = connect(
            stack, client, b, capabilities=["silence_suppression", "opus"]
        )
        assert negotiated["encoding"] == "opus"
        command(wa, "voice.state", {"session_id": sa, "muted": False})
        command(wb, "heartbeat")
        keepalive = ab.receive_json()
        assert keepalive["type"] == "voice.idle"
