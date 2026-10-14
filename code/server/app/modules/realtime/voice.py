"""Small-room mixer shared by WebRTC and native Godot audio WebSockets.

This is an MCU, not an SFU: listeners receive one mono mix. Per-source policy is
checked when queued AND when played. Install requirements-voice.txt to enable.
"""

import asyncio
import base64
import hashlib
import hmac
import importlib.util
import time
from array import array
from collections import deque
from dataclasses import dataclass, field
from fractions import Fraction
from app.core.config import settings
from app.core.exceptions import AppError
from app.modules.realtime.runtime import runtime


def ensure_media_available():
    if not settings.voice_enabled:
        raise AppError("VOICE_DISABLED", "Voice is not enabled on this server", 503)
    if importlib.util.find_spec("aiortc") is None:
        raise AppError(
            "MEDIA_UNAVAILABLE", "Install the server voice dependencies", 503
        )


def ice_servers(identity):
    result = []
    urls = [u.strip() for u in settings.voice_stun_urls.split(",") if u.strip()]
    if urls:
        result.append({"urls": urls})
    turn = [u.strip() for u in settings.voice_turn_urls.split(",") if u.strip()]
    if turn:
        username = f"{int(time.time()) + settings.voice_turn_ttl_seconds}:{identity}"
        credential = base64.b64encode(
            hmac.new(
                settings.voice_turn_secret.encode(), username.encode(), hashlib.sha1
            ).digest()
        ).decode()
        result.append({"urls": turn, "username": username, "credential": credential})
    return result


@dataclass
class MediaPeer:
    pid: int
    generation: str
    session_id: str
    pc: object
    incoming: deque = field(default_factory=lambda: deque(maxlen=3))
    outgoing: asyncio.Queue = field(default_factory=lambda: asyncio.Queue(maxsize=2))
    consumers: list = field(default_factory=list)
    created: float = field(default_factory=time.monotonic)
    negotiated: bool = False
    last_spoke: float = 0


class VoiceHub:
    def __init__(self):
        self.peers = {}
        self.ticker = None

    async def offer(self, pid, generation, request):
        ensure_media_available()
        from aiortc import (
            RTCPeerConnection,
            RTCConfiguration,
            RTCIceServer,
            RTCSessionDescription,
            MediaStreamTrack,
        )
        from aiortc.sdp import SessionDescription
        from av import AudioFrame

        if not runtime.media_valid(pid, generation, request.session_id):
            raise AppError("VOICE_SESSION_EXPIRED", "Join voice again", 409)
        if request.session_id in self.peers:
            raise AppError(
                "VOICE_ALREADY_NEGOTIATED", "Leave and rejoin to negotiate again", 409
            )
        try:
            parsed = SessionDescription.parse(request.sdp)
            if (
                len(parsed.media) != 1
                or parsed.media[0].kind != "audio"
                or parsed.media[0].direction not in ("sendrecv", "recvonly")
            ):
                raise ValueError("Expected one audio transceiver")
        except (ValueError, AssertionError, IndexError, KeyError):
            raise AppError(
                "INVALID_VOICE_OFFER", "Offer must contain one audio transceiver", 422
            )
        pc = RTCPeerConnection(
            RTCConfiguration(
                iceServers=[RTCIceServer(**v) for v in ice_servers(str(pid))]
            )
        )
        peer = MediaPeer(pid, generation, request.session_id, pc)
        self.peers[request.session_id] = peer
        if self.ticker is None or self.ticker.done():
            self.ticker = asyncio.create_task(self._tick())
        hub = self

        class MixedAudioTrack(MediaStreamTrack):
            kind = "audio"

            def __init__(self):
                super().__init__()
                self.pts = 0

            async def recv(self):
                contributions = await peer.outgoing.get()
                samples = hub.mix(peer, contributions)
                frame = AudioFrame(format="s16", layout="mono", samples=960)
                frame.planes[0].update(samples.tobytes())
                frame.sample_rate = 48000
                frame.pts, frame.time_base = self.pts, Fraction(1, 48000)
                self.pts += 960
                return frame

        @pc.on("track")
        def on_track(track):
            peer.consumers.append(asyncio.create_task(self._consume(peer, track)))

        @pc.on("connectionstatechange")
        async def state_changed():
            if pc.connectionState in ("failed", "closed"):
                await self.close(peer.session_id)

        try:
            pc.addTrack(MixedAudioTrack())
            async with asyncio.timeout(12):
                await pc.setRemoteDescription(
                    RTCSessionDescription(sdp=request.sdp, type="offer")
                )
                await pc.setLocalDescription(await pc.createAnswer())
            if not runtime.media_valid(pid, generation, request.session_id):
                raise AppError(
                    "VOICE_SESSION_EXPIRED",
                    "Voice authorization expired during negotiation",
                    409,
                )
            peer.negotiated = True
            return {
                "type": "answer",
                "sdp": pc.localDescription.sdp,
                "session_id": peer.session_id,
            }
        except BaseException:
            await self.close(peer.session_id)
            raise

    async def _consume(self, peer, track):
        from av import AudioResampler
        from aiortc.mediastreams import MediaStreamError

        resampler = AudioResampler(
            format="s16", layout="mono", rate=48000, frame_size=960
        )
        try:
            while True:
                frame = await track.recv()
                for output in resampler.resample(frame):
                    if not runtime.media_valid(
                        peer.pid, peer.generation, peer.session_id
                    ):
                        peer.incoming.clear()
                        continue
                    with runtime.lock:
                        state = runtime.connection(peer.pid, peer.generation)
                        if state.muted or state.deafened:
                            peer.incoming.clear()
                            continue
                    samples = array("h")
                    samples.frombytes(bytes(output.planes[0])[: output.samples * 2])
                    if len(samples) == 960:
                        if max(abs(x) for x in samples) > 500:
                            peer.last_spoke = time.monotonic()
                        peer.incoming.append((time.monotonic(), samples))
        except (MediaStreamError, asyncio.CancelledError):
            pass
        except Exception:
            # A malformed/failed media stream must never leave a stale publisher.
            await self.close(peer.session_id)

    def mix(self, listener, contributions):
        mixed = [0.0] * 960
        if runtime.media_valid(listener.pid, listener.generation, listener.session_id):
            for source, timestamp, samples in contributions:
                if time.monotonic() - timestamp > 0.12 or not runtime.media_valid(
                    source.pid, source.generation, source.session_id
                ):
                    continue
                gain = runtime.audible(source.pid, listener.pid)
                if gain:
                    for i, sample in enumerate(samples):
                        mixed[i] += sample * gain
        return array("h", (max(-32768, min(32767, int(x))) for x in mixed))

    async def _tick(self):
        deadline = time.monotonic()
        try:
            while self.peers:
                now = time.monotonic()
                sources = []
                for peer in list(self.peers.values()):
                    valid = runtime.media_valid(
                        peer.pid, peer.generation, peer.session_id
                    )
                    if not valid:
                        # Allow in-flight ICE gathering to finish, but never mix
                        # audio during this grace period or after a lost lease.
                        if (
                            (
                                peer.negotiated
                                and not runtime.connection_valid(
                                    peer.pid, peer.generation, peer.session_id
                                )
                            )
                            or now - peer.created > 15
                            and not peer.negotiated
                        ):
                            await self.close(peer.session_id)
                        peer.incoming.clear()
                        continue
                    while peer.incoming and now - peer.incoming[0][0] > 0.06:
                        peer.incoming.popleft()
                    if peer.incoming:
                        timestamp, samples = peer.incoming.popleft()
                        sources.append((peer, timestamp, samples))
                for listener in list(self.peers.values()):
                    contributions = [
                        s
                        for s in sources
                        if runtime.audible(s[0].pid, listener.pid) > 0
                    ]
                    if listener.outgoing.full():
                        listener.outgoing.get_nowait()
                    listener.outgoing.put_nowait(contributions)
                deadline += 0.02
                if deadline < time.monotonic() - 0.02:
                    deadline = time.monotonic()
                await asyncio.sleep(max(0, deadline - time.monotonic()))
        except asyncio.CancelledError:
            pass

    def speakers(self, listener):
        now = time.monotonic()
        return sorted(
            {
                p.pid
                for p in self.peers.values()
                if now - p.last_spoke < 0.3 and runtime.audible(p.pid, listener) > 0
            }
        )

    async def close(self, session_id):
        peer = self.peers.pop(session_id, None)
        if peer is None:
            return
        # Do not let an old connection's cleanup close a new voice session.
        with runtime.lock:
            row = runtime.connections.get(peer.pid)
            if row and row.generation == peer.generation and row.voice_id == session_id:
                row.voice_id = None
                row.muted = True
        for task in peer.consumers:
            if task is not asyncio.current_task():
                task.cancel()
        await peer.pc.close()
        await asyncio.gather(
            *(t for t in peer.consumers if t is not asyncio.current_task()),
            return_exceptions=True,
        )

    async def close_connection(self, pid, generation):
        for peer in list(self.peers.values()):
            if peer.pid == pid and peer.generation == generation:
                await self.close(peer.session_id)

    async def shutdown(self):
        for session_id in list(self.peers):
            await self.close(session_id)
        if self.ticker:
            self.ticker.cancel()
            await asyncio.gather(self.ticker, return_exceptions=True)
            self.ticker = None


voice_hub = VoiceHub()
