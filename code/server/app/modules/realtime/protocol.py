"""Realtime wire protocol: one inbound message in, one reply packet out.

This is the business half of the socket. It validates a message against the
protocol rules, runs the matching command, applies the voice/policy state
machine, and assembles the authoritative reply. It knows nothing about
WebSockets, asyncio, sockets or ownership -- ``session.py`` owns all of that and
calls ``RealtimeProtocol.step`` synchronously from a worker thread.

Two protocol versions are supported. Version 1 is the original
request/response-per-frame socket. Version 2 adds a ``connection_id``/
``sequence`` pair for ordering, a ``request_id`` on every state-changing command,
and an ``events`` list carrying diffs instead of requiring the client to diff
whole snapshots itself.
"""

from typing import Annotated

from fastapi.encoders import jsonable_encoder
from pydantic import Field, TypeAdapter, ValidationError

from app.core.exceptions import AppError
from app.core.rate_limit import limiter
from app.modules.auth.service import AuthService
from app.modules.realtime.proximity import proximity_view
from app.modules.realtime.runtime import runtime
from app.modules.realtime.schemas import (
    EmoteRequest,
    EnterRequest,
    MoveRequest,
    NearbyChatRequest,
)
from app.modules.realtime.service import RealtimeService
from app.modules.realtime.voice import ensure_media_available, ice_servers
from app.modules.realtime.voice_schemas import (
    DismissRequest,
    VoiceOfferRequest,
    VoiceStateRequest,
)

REQUEST_ID_ADAPTER = TypeAdapter(
    Annotated[str, Field(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")]
)

# Message types a version 2 client may send. Version 1 may only send the passive
# ones, so a command that depends on ordering or idempotency is refused rather
# than silently executed without the guarantees its client expects.
PASSIVE_TYPES = ("snapshot", "heartbeat")
COMMAND_TYPES = ("enter", "move", "chat", "emote")
VOICE_TYPES = (
    "voice.join",
    "voice.leave",
    "voice.state",
    "voice.offer",
    "proximity.dismiss",
)
ALL_TYPES = PASSIVE_TYPES + COMMAND_TYPES + VOICE_TYPES
VOICE_TRANSPORTS = ("webrtc-mixed-audio", "pcm-websocket")

# Failures that mean "this session is over", not "this message was bad". The
# socket tears the connection down instead of sending an error and carrying on.
SESSION_OVER_CODES = ("VISIT_ENDED", "SESSION_EXPIRED")


class RealtimeProtocol:
    """Stateless-per-call protocol handler bound to one session's database."""

    def __init__(self, db):
        self.db = db

    def step(self, token, message, protocol=1, generation=None):
        """Handle one inbound frame and return the reply packet.

        Never raises for a client error: a malformed or rejected message becomes
        an ``error`` packet, because the socket loop is the only thing that can
        decide whether to close the connection.
        """
        request_id = None
        pid = None
        try:
            player = AuthService(self.db).authenticate(token)
            pid = player.id
            if protocol == 2:
                with runtime.lock:
                    runtime.connection(pid, generation)
            if "request_id" in message:
                request_id = REQUEST_ID_ADAPTER.validate_python(message["request_id"])
            if not isinstance(message.get("data", {}), dict):
                raise AppError("VALIDATION_ERROR", "Expected an object payload", 422)
            service = RealtimeService(self.db)
            kind = message.get("type", "snapshot")
            events = []
            request_id = self._dispatch(
                service, pid, message, kind, protocol, request_id, events
            )
            if kind == "heartbeat":
                service.heartbeat(pid)
            data = service.snapshot(pid)
            if protocol == 2:
                return self._protocol_two_reply(
                    pid, generation, kind, message, data, events, request_id
                )
            return jsonable_encoder({"type": "snapshot", "data": data})
        except AppError as exc:
            if pid and protocol == 2 and exc.code in SESSION_OVER_CODES:
                runtime.invalidate({pid}, leave=True)
            return {
                "type": "error",
                "error": exc.code,
                "message": exc.message,
                "status": exc.status,
                "request_id": request_id,
            }
        except ValidationError:
            return {
                "type": "error",
                "error": "VALIDATION_ERROR",
                "message": "Invalid realtime payload",
                "status": 422,
                "request_id": request_id,
            }
        finally:
            # A socket's database session spans every frame it sends, so each
            # frame must end with a clean transaction or the next one inherits a
            # half-applied read. Services still own their own write boundaries:
            # anything they committed above is durable, and this only discards the
            # speculative reads that opened an implicit transaction.
            self.db.rollback()

    def _dispatch(self, service, pid, message, kind, protocol, request_id, events):
        """Route one validated message to its command handler.

        Returns the effective request id, which ``chat`` may fill in from the
        payload when the envelope did not carry one.
        """
        if kind == "enter":
            request = EnterRequest.model_validate(message.get("data", {}))
            service.enter(pid, request.owner_id)
        elif kind == "move":
            service.move(pid, MoveRequest.model_validate(message.get("data", {})))
        elif kind == "chat":
            request = NearbyChatRequest.model_validate(message.get("data", {}))
            if request_id and request.request_id and request_id != request.request_id:
                raise AppError("VALIDATION_ERROR", "Request IDs must agree", 422)
            request_id = request_id or request.request_id
            if protocol == 2 and not request_id:
                raise AppError("VALIDATION_ERROR", "Text requires a request_id", 422)
            receipt = service.chat(pid, request.body, request_id)
            events.append({"type": "chat.accepted", "request_id": request_id, "data": receipt})
        elif kind == "emote":
            service.emote(pid, EmoteRequest.model_validate(message.get("data", {})).emote)
        elif kind not in ALL_TYPES:
            raise AppError("INVALID_MESSAGE", "Unknown realtime message type")
        elif protocol != 2 and kind != "snapshot":
            raise AppError(
                "PROTOCOL_REQUIRED", "This command requires protocol version 2", 400
            )
        return request_id

    def _protocol_two_reply(
        self, pid, generation, kind, message, data, events, request_id
    ):
        """Refresh policy leases, run the voice state machine, shape the frame."""
        revision = runtime.policy_revision()
        view = proximity_view(self.db, pid)
        runtime.apply(pid, generation, revision, view)
        if kind.startswith("voice."):
            limiter.check(f"voice-control:{pid}", 30, 10)
        if kind == "voice.join":
            session_id = self._voice_join(pid, generation, message)
            events.append(
                {
                    "type": "voice.ready",
                    "request_id": request_id,
                    "data": {
                        "session_id": session_id,
                        "ice_servers": ice_servers(str(pid)),
                        "heartbeat_seconds": 0.5,
                        "muted": runtime.view(pid, generation)["voice"]["muted"],
                        "transport": self._transport(message),
                    },
                }
            )
        elif kind == "voice.leave":
            runtime.leave(pid, generation)
            events.append({"type": "voice.left", "request_id": request_id})
        elif kind == "voice.state":
            request = VoiceStateRequest.model_validate(message.get("data", {}))
            runtime.state(pid, generation, **request.model_dump())
        elif kind == "voice.offer":
            request = VoiceOfferRequest.model_validate(message.get("data", {}))
            if not runtime.media_valid(pid, generation, request.session_id):
                raise AppError("VOICE_SESSION_EXPIRED", "Join voice again", 409)
            # Negotiation itself runs off-loop in the session; this only admits it.
            events.append({"type": "voice.offer.pending", "request_id": request_id})
        elif kind == "proximity.dismiss":
            request = DismissRequest.model_validate(message.get("data", {}))
            runtime.dismiss(pid, generation, request.target_id)
        state = runtime.view(pid, generation)
        data["proximity"] = {**view, "nearby": state["nearby"]}
        data["voice"] = state["voice"]
        data["social_revision"] = view["social_revision"]
        return jsonable_encoder(
            {
                "type": "snapshot",
                "data": data,
                "events": events,
                "request_id": request_id,
            }
        )

    @staticmethod
    def _transport(message):
        transport = message.get("data", {}).get("transport", "webrtc-mixed-audio")
        if transport not in VOICE_TRANSPORTS:
            raise AppError("INVALID_TRANSPORT", "Unsupported voice transport", 422)
        return transport

    @staticmethod
    def _voice_join(pid, generation, message):
        """Admit the client to a voice session and return its id."""
        transport = RealtimeProtocol._transport(message)
        if transport == "webrtc-mixed-audio":
            ensure_media_available()
        return runtime.join(pid, generation)