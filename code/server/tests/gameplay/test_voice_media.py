"""Real local WebRTC negotiation and encrypted audio delivery (optional media extra)."""

import asyncio
import math
import time
from array import array
from fractions import Fraction
import pytest
from app.core.config import settings
from app.modules.realtime.runtime import runtime
from app.modules.realtime.voice import VoiceHub, MediaPeer, ice_servers
from app.modules.realtime.voice_schemas import VoiceOfferRequest


def authorize(pid, generation, others):
    view = {
        "room": "campus",
        "room_epoch": 1,
        "voice_privacy": "friends",
        "proximity_prompts": True,
        "nearby": [
            {
                "player_id": target,
                "friend": True,
                "distance": 100,
                "can_text": True,
                "can_voice": True,
            }
            for target in others
        ],
    }
    runtime.heartbeat(pid, generation)
    runtime.apply(pid, generation, runtime.policy_revision(), view)


def test_mixer_checks_revocation_at_playback(monkeypatch):
    monkeypatch.setattr(settings, "voice_enabled", True)
    a, b = runtime.attach(901), runtime.attach(902)
    try:
        authorize(901, a, [902])
        authorize(902, b, [901])
        sa, sb = runtime.join(901, a), runtime.join(902, b)
        runtime.state(901, a, sa, False, False, [])
        source = MediaPeer(901, a, sa, None)
        listener = MediaPeer(902, b, sb, None)
        samples = [(source, time.monotonic(), array("h", [2000] * 960))]
        hub = VoiceHub()
        assert max(hub.mix(listener, samples)) == 2000
        runtime.invalidate({901})
        assert max(hub.mix(listener, samples)) == 0
    finally:
        runtime.detach(901, a)
        runtime.detach(902, b)


def test_turn_uses_expiring_identity_scoped_credentials(monkeypatch):
    monkeypatch.setattr(settings, "voice_turn_urls", "turn:localhost:3478")
    monkeypatch.setattr(settings, "voice_turn_secret", "test-secret")
    servers = ice_servers("42")
    turn = servers[-1]
    assert turn["username"].endswith(":42")
    assert int(turn["username"].split(":")[0]) > time.time()
    assert turn["credential"] and turn["credential"] != "test-secret"


def test_real_webrtc_audio_and_server_mute(monkeypatch):
    pytest.importorskip("aiortc")
    from aiortc import (
        RTCPeerConnection,
        RTCConfiguration,
        RTCSessionDescription,
        MediaStreamTrack,
    )
    from av import AudioFrame

    monkeypatch.setattr(settings, "voice_enabled", True)
    monkeypatch.setattr(settings, "voice_stun_urls", "")
    monkeypatch.setattr(settings, "voice_turn_urls", "")

    class Tone(MediaStreamTrack):
        kind = "audio"

        def __init__(self):
            super().__init__()
            self.pts = 0
            self.started = time.monotonic()

        async def recv(self):
            await asyncio.sleep(
                max(0, self.started + self.pts / 48000 - time.monotonic())
            )
            samples = array(
                "h",
                (
                    int(6000 * math.sin(2 * math.pi * 440 * (self.pts + i) / 48000))
                    for i in range(960)
                ),
            )
            frame = AudioFrame(format="s16", layout="mono", samples=960)
            frame.planes[0].update(samples.tobytes())
            frame.sample_rate, frame.pts, frame.time_base = (
                48000,
                self.pts,
                Fraction(1, 48000),
            )
            self.pts += 960
            return frame

    async def scenario():
        hub = VoiceHub()
        pcs, received = [], {}
        owners = {pid: runtime.attach(pid) for pid in (911, 912)}
        sessions = {}
        keepalive = None

        async def keep_alive():
            while True:
                for pid, generation in owners.items():
                    authorize(
                        pid, generation, [other for other in owners if other != pid]
                    )
                await asyncio.sleep(0.2)

        try:
            for pid, generation in owners.items():
                authorize(pid, generation, [other for other in owners if other != pid])
                sessions[pid] = runtime.join(pid, generation)
            keepalive = asyncio.create_task(keep_alive())
            for pid, generation in owners.items():
                pc = RTCPeerConnection(RTCConfiguration(iceServers=[]))
                pcs.append(pc)

                @pc.on("track")
                def track_received(track, player=pid):
                    received[player] = track

                pc.addTrack(Tone())
                await pc.setLocalDescription(await pc.createOffer())
                answer = await hub.offer(
                    pid,
                    generation,
                    VoiceOfferRequest(
                        session_id=sessions[pid], sdp=pc.localDescription.sdp
                    ),
                )
                await pc.setRemoteDescription(
                    RTCSessionDescription(sdp=answer["sdp"], type="answer")
                )
            runtime.state(911, owners[911], sessions[911], False, False, [])

            # 912 stays muted: it can listen, while 911 must receive silence.
            async def amplitude(pid):
                frame = await received[pid].recv()
                values = array("h")
                values.frombytes(
                    bytes(frame.planes[0])[
                        : frame.samples * len(frame.layout.channels) * 2
                    ]
                )
                return max(abs(x) for x in values)

            async def hear_tone():
                for _ in range(150):
                    if await amplitude(912) > 500:
                        return
                raise AssertionError("No authorized tone received")

            await asyncio.wait_for(hear_tone(), timeout=10)
            assert await asyncio.wait_for(amplitude(911), timeout=3) == 0
            runtime.state(911, owners[911], sessions[911], True, False, [])
            # Drain bounded media/jitter queues, then require sustained silence.
            for _ in range(30):
                await asyncio.wait_for(amplitude(912), timeout=3)
            for _ in range(5):
                assert await asyncio.wait_for(amplitude(912), timeout=3) <= 5
            for pc in pcs:
                assert pc.connectionState == "connected"
        finally:
            if keepalive:
                keepalive.cancel()
                await asyncio.gather(keepalive, return_exceptions=True)
            await hub.shutdown()
            await asyncio.gather(*(pc.close() for pc in pcs))
            for pid, generation in owners.items():
                runtime.detach(pid, generation)

    asyncio.run(scenario())
