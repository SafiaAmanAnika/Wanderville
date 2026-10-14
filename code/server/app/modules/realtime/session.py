"""WebSocket connection lifecycle for realtime.

Everything that is *about a socket* lives here: the origin check, the auth
handshake, frame size limits, the idle-snapshot loop, per-connection sequencing,
diffing consecutive snapshots into ``events``, off-loop voice negotiation, and
teardown. The command semantics are in ``protocol.py`` and the shared voice/lease
state in ``runtime.py``; neither knows a WebSocket exists.

The ownership invariant is checked after every ``await``: a replaced socket must
not be able to send anything, close its successor, or mutate its successor's
state.
"""

import asyncio
import json

from starlette.concurrency import run_in_threadpool
from starlette.websockets import WebSocketDisconnect

from app.core.config import settings
from app.core.exceptions import AppError
from app.core.rate_limit import limiter
from app.modules.auth.service import AuthService
from app.modules.realtime.connections import sockets
from app.modules.realtime.protocol import RealtimeProtocol
from app.modules.realtime.runtime import runtime
from app.modules.realtime.service import RealtimeService
from app.modules.realtime.voice import voice_hub
from app.modules.realtime.voice_schemas import VoiceOfferRequest

# Protocol 1 predates the connection_id/sequence pair and the large gift/voice
# payloads, so its frame ceiling is deliberately much smaller.
MAX_FRAME_V1 = 8192
MAX_FRAME_V2 = 65536
AUTH_TIMEOUT_SECONDS = 10
READ_TIMEOUT_SECONDS = 0.2
SEND_TIMEOUT_SECONDS = 5
IDLE_TICK_SECONDS = 0.05


class RealtimeSession:
    """One authenticated socket, from handshake to teardown."""

    def __init__(self, websocket, db):
        self.websocket = websocket
        self.db = db
        self.protocol = RealtimeProtocol(db)
        # Identity token for socket ownership; distinct from the voice generation.
        self.owner = object()
        self.pid = None
        self.generation = None
        self.protocol_version = 1
        self.sequence = 0
        self.tasks = set()
        self.send_lock = asyncio.Lock()
        # Previous frame's projections, so each send can emit only what changed.
        self.seen = {"proximity": None, "voice": None, "social": None}
        self.seen_messages = set()

    # ------------------------------------------------------------- transport

    async def _send(self, packet):
        """Serialize, stamp and write one frame, emitting protocol-2 diffs."""
        async with self.send_lock:
            if self.protocol_version == 2 and packet.get("type") == "snapshot":
                events = packet.setdefault("events", [])
                self._diff(packet["data"], events)
            if self.protocol_version == 2:
                self.sequence += 1
                packet = {
                    **packet,
                    "connection_id": self.generation,
                    "sequence": self.sequence,
                }
            await asyncio.wait_for(
                self.websocket.send_json(packet), timeout=SEND_TIMEOUT_SECONDS
            )

    def _diff(self, data, events):
        """Turn consecutive snapshots into the smallest event set that explains them."""
        scope = {"room": data["room"], "room_epoch": data["room_epoch"]}
        proximity = data.get("proximity")
        if proximity != self.seen["proximity"]:
            events.append({"type": "proximity.updated", **scope, "data": proximity})
            self.seen["proximity"] = proximity
        voice = data.get("voice")
        if voice is not None:
            voice["speakers"] = voice_hub.speakers(self.pid)
        if voice != self.seen["voice"]:
            events.append({"type": "voice.updated", **scope, "data": voice})
            self.seen["voice"] = voice
        revision = data.get("social_revision")
        if revision != self.seen["social"]:
            events.append({"type": "social.updated", "data": {"revision": revision}})
            self.seen["social"] = revision
        messages = data.get("messages", [])
        current = {message["id"] for message in messages}
        for message in messages:
            if message["id"] not in self.seen_messages:
                events.append({"type": "chat.message", **scope, "data": message})
        self.seen_messages.intersection_update(current)
        self.seen_messages.update(current)

    async def _receive_text(self, timeout):
        """One text frame, or ``None`` when the peer sent a binary frame."""
        packet = await asyncio.wait_for(self.websocket.receive(), timeout=timeout)
        if packet["type"] == "websocket.disconnect":
            raise WebSocketDisconnect(packet.get("code", 1000))
        raw = packet.get("text")
        if raw is None:
            await self.websocket.close(code=1003)
        return raw

    async def _step(self, message):
        """Run one protocol step on a worker thread; it blocks on the database."""
        return await run_in_threadpool(
            self.protocol.step,
            self._token,
            message,
            self.protocol_version,
            self.generation,
        )

    # -------------------------------------------------------------- lifecycle

    async def run(self):
        if not self._origin_allowed():
            await self.websocket.close(code=1008)
            return
        await self.websocket.accept()
        try:
            if not await self._handshake():
                return
            if not await self._serve():
                return
        except WebSocketDisconnect:
            return
        except (asyncio.TimeoutError, ValueError, AppError):
            await self.websocket.close(code=1008)
        finally:
            await self._teardown()

    def _origin_allowed(self):
        origin = self.websocket.headers.get("origin")
        return not origin or origin in settings.allowed_origins or "*" in settings.allowed_origins

    async def _handshake(self):
        """Authenticate the first frame and place the player in their room."""
        raw = await self._receive_text(AUTH_TIMEOUT_SECONDS)
        if raw is None:
            return False
        if len(raw.encode("utf-8")) > MAX_FRAME_V1:
            await self.websocket.close(code=1009)
            return False
        first = json.loads(raw)
        if (
            not isinstance(first, dict)
            or first.get("type") != "auth"
            or not isinstance(first.get("token"), str)
        ):
            await self.websocket.close(code=1008)
            return False
        version = first.get("protocol_version", 1)
        if type(version) is not int or version not in (1, 2):
            await self.websocket.close(code=1008)
            return False
        self.protocol_version = version
        self._token = first["token"]
        try:
            player = await run_in_threadpool(
                AuthService(self.db).authenticate, self._token
            )
            self.pid = player.id
            sockets.claim(self.pid, self.owner)
            self.generation = runtime.attach(self.pid)
        except AppError:
            self.pid = None
        reply = await self._step({"type": "enter"})
        await self._send(reply)
        if reply.get("type") == "error":
            await self.websocket.close(code=1008)
            return False
        return True

    async def _serve(self):
        """Read/respond until the socket dies or is replaced."""
        while True:
            if not sockets.owns(self.pid, self.owner):
                await self.websocket.close(code=1008)
                return False
            received = False
            try:
                raw = await self._receive_text(READ_TIMEOUT_SECONDS)
                if raw is None:
                    return False
                ceiling = MAX_FRAME_V2 if self.protocol_version == 2 else MAX_FRAME_V1
                if len(raw.encode("utf-8")) > ceiling:
                    await self.websocket.close(code=1009)
                    return False
                message = json.loads(raw)
                if not isinstance(message, dict):
                    await self.websocket.close(code=1008)
                    return False
                received = True
            except asyncio.TimeoutError:
                message = {"type": "snapshot"}
            # Recheck after the await: a socket replaced while this one was
            # suspended must not act on its successor's behalf.
            if not sockets.owns(self.pid, self.owner):
                await self.websocket.close(code=1008)
                return False
            if received:
                limiter.check(f"realtime:{self.pid}", 60, 1)
                runtime.heartbeat(self.pid, self.generation)
            reply = await self._step(message)
            if not sockets.owns(self.pid, self.owner):
                return False
            await self._send(reply)
            await self._after_send(message, reply)
            await asyncio.sleep(IDLE_TICK_SECONDS)

    async def _after_send(self, message, reply):
        """Start voice negotiation and honour fatal replies."""
        if (
            self.protocol_version == 2
            and reply.get("type") != "error"
            and message.get("type") == "voice.offer"
        ):
            if not self.tasks:
                task = asyncio.create_task(self._negotiate(message))
                self.tasks.add(task)
                task.add_done_callback(self.tasks.discard)
            else:
                await self._send(
                    {
                        "type": "error",
                        "error": "VOICE_NEGOTIATING",
                        "message": "Voice negotiation is already in progress",
                        "request_id": message.get("request_id"),
                    }
                )
        if reply.get("status") == 401 or (
            self.protocol_version == 1 and reply.get("status") == 403
        ):
            await self.websocket.close(code=1008)

    async def _negotiate(self, message):
        """Run WebRTC answer generation off the read loop."""
        try:
            answer = await voice_hub.offer(
                self.pid, self.generation, VoiceOfferRequest.model_validate(message["data"])
            )
            if sockets.owns(self.pid, self.owner):
                await self._send(
                    {
                        "type": "voice.answer",
                        "data": answer,
                        "request_id": message.get("request_id"),
                    }
                )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            # Never echo SDP, ICE candidates or provider errors in logs/replies.
            if sockets.owns(self.pid, self.owner):
                try:
                    await self._send(
                        {
                            "type": "error",
                            "error": exc.code if isinstance(exc, AppError) else "MEDIA_UNAVAILABLE",
                            "message": exc.message
                            if isinstance(exc, AppError)
                            else "Voice negotiation failed; leave and rejoin",
                            "request_id": message.get("request_id"),
                        }
                    )
                except (WebSocketDisconnect, RuntimeError, TimeoutError):
                    pass

    async def _teardown(self):
        for task in self.tasks:
            task.cancel()
        if self.tasks:
            await asyncio.gather(*self.tasks, return_exceptions=True)
        if self.pid is None:
            return
        await voice_hub.close_connection(self.pid, self.generation)
        runtime.detach(self.pid, self.generation)
        if sockets.release(self.pid, self.owner):
            await run_in_threadpool(RealtimeService(self.db).leave, self.pid)