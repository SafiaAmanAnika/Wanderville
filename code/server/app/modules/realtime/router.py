from fastapi import APIRouter, Depends, WebSocket
from sqlalchemy.orm import Session
from app.core.responses import success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.realtime.schemas import (
    EnterRequest,
    MoveRequest,
    NearbyChatRequest,
    EmoteRequest,
)
from app.modules.realtime.service import RealtimeService

router = APIRouter(prefix="/realtime", tags=["realtime"])
# One Uvicorn worker owns the sockets. A replaced socket cannot expire its successor.
_socket_owners = {}


@router.post("/enter")
def enter(
    payload: EnterRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).enter(pid, payload.owner_id))


@router.post("/move")
def move(
    payload: MoveRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).move(pid, payload))


@router.get("/snapshot")
def snapshot(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(RealtimeService(db).snapshot(pid))


@router.post("/chat")
def chat(
    payload: NearbyChatRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).chat(pid, payload.body, payload.request_id))


@router.post("/emote")
def emote(
    payload: EmoteRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).emote(pid, payload.emote))


@router.get("/proximity")
def proximity(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    from app.modules.realtime.proximity import proximity_view

    return success(proximity_view(db, pid))


def socket_step(db, token, message, protocol=1, generation=None):
    from app.modules.auth.service import AuthService
    from app.core.exceptions import AppError
    from app.core.rate_limit import limiter
    from fastapi.encoders import jsonable_encoder
    from pydantic import ValidationError, TypeAdapter
    from typing import Annotated
    from pydantic import Field
    from app.modules.realtime.runtime import runtime
    from app.modules.realtime.proximity import proximity_view
    from app.modules.realtime.voice_schemas import (
        VoiceStateRequest,
        VoiceOfferRequest,
        DismissRequest,
    )
    from app.modules.realtime.voice import ensure_media_available, ice_servers

    request_id = None
    pid = None
    try:
        player = AuthService(db).authenticate(token)
        pid = player.id
        if protocol == 2:
            with runtime.lock:
                runtime.connection(pid, generation)
        if "request_id" in message:
            request_id = TypeAdapter(
                Annotated[
                    str, Field(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
                ]
            ).validate_python(message["request_id"])
        if not isinstance(message.get("data", {}), dict):
            raise AppError("VALIDATION_ERROR", "Expected an object payload", 422)
        service = RealtimeService(db)
        kind = message.get("type", "snapshot")
        events = []
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
            events.append(
                {"type": "chat.accepted", "request_id": request_id, "data": receipt}
            )
        elif kind == "emote":
            service.emote(
                pid, EmoteRequest.model_validate(message.get("data", {})).emote
            )
        elif kind not in (
            "snapshot",
            "heartbeat",
            "voice.join",
            "voice.leave",
            "voice.state",
            "voice.offer",
            "proximity.dismiss",
        ):
            raise AppError("INVALID_MESSAGE", "Unknown realtime message type")
        elif protocol != 2 and kind != "snapshot":
            raise AppError(
                "PROTOCOL_REQUIRED", "This command requires protocol version 2", 400
            )
        if kind == "heartbeat":
            service.heartbeat(pid)
        data = service.snapshot(pid)
        if protocol == 2:
            revision = runtime.policy_revision()
            view = proximity_view(db, pid)
            runtime.apply(pid, generation, revision, view)
            if kind.startswith("voice."):
                limiter.check(f"voice-control:{pid}", 30, 10)
            if kind == "voice.join":
                transport = message.get("data", {}).get("transport", "webrtc-mixed-audio")
                if transport not in ("webrtc-mixed-audio", "pcm-websocket"):
                    raise AppError("INVALID_TRANSPORT", "Unsupported voice transport", 422)
                if transport == "webrtc-mixed-audio":
                    ensure_media_available()
                session_id = runtime.join(pid, generation)
                events.append(
                    {
                        "type": "voice.ready",
                        "request_id": request_id,
                        "data": {
                            "session_id": session_id,
                            "ice_servers": ice_servers(str(pid)),
                            "heartbeat_seconds": 0.5,
                            "muted": runtime.view(pid, generation)["voice"]["muted"],
                            "transport": transport,
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
        return jsonable_encoder({"type": "snapshot", "data": data})
    except AppError as exc:
        if pid and protocol == 2 and exc.code in ("VISIT_ENDED", "SESSION_EXPIRED"):
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
        db.rollback()


async def socket_text(websocket):
    from starlette.websockets import WebSocketDisconnect

    packet = await websocket.receive()
    if packet["type"] == "websocket.disconnect":
        raise WebSocketDisconnect(packet.get("code", 1000))
    raw = packet.get("text")
    if raw is None:
        await websocket.close(code=1003)
    return raw


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    import asyncio
    import json
    from starlette.concurrency import run_in_threadpool
    from starlette.websockets import WebSocketDisconnect
    from app.core.config import settings
    from app.core.rate_limit import limiter
    from app.modules.auth.service import AuthService
    from app.core.exceptions import AppError
    from app.modules.realtime.runtime import runtime
    from app.modules.realtime.voice import voice_hub
    from app.modules.realtime.voice_schemas import VoiceOfferRequest

    origin = websocket.headers.get("origin")
    if (
        origin
        and origin not in settings.allowed_origins
        and "*" not in settings.allowed_origins
    ):
        await websocket.close(code=1008)
        return
    owner = object()
    pid, generation = None, None
    tasks = set()
    send_lock = asyncio.Lock()
    sequence = 0
    protocol = 1
    previous_proximity = None
    previous_voice = None
    previous_social = None
    seen_messages = set()

    async def send(packet):
        nonlocal sequence, previous_proximity, previous_voice, previous_social
        async with send_lock:
            if protocol == 2 and packet.get("type") == "snapshot":
                data = packet["data"]
                events = packet.setdefault("events", [])
                scope = {"room": data["room"], "room_epoch": data["room_epoch"]}
                proximity = data.get("proximity")
                if proximity != previous_proximity:
                    events.append(
                        {"type": "proximity.updated", **scope, "data": proximity}
                    )
                    previous_proximity = proximity
                voice = data.get("voice")
                if voice is not None:
                    voice["speakers"] = voice_hub.speakers(pid)
                if voice != previous_voice:
                    events.append({"type": "voice.updated", **scope, "data": voice})
                    previous_voice = voice
                revision = data.get("social_revision")
                if revision != previous_social:
                    events.append(
                        {"type": "social.updated", "data": {"revision": revision}}
                    )
                    previous_social = revision
                messages = data.get("messages", [])
                current_ids = {m["id"] for m in messages}
                for message in messages:
                    if message["id"] not in seen_messages:
                        events.append(
                            {"type": "chat.message", **scope, "data": message}
                        )
                seen_messages.intersection_update(current_ids)
                seen_messages.update(current_ids)
            if protocol == 2:
                sequence += 1
                packet = {**packet, "connection_id": generation, "sequence": sequence}
            await asyncio.wait_for(websocket.send_json(packet), timeout=5)

    async def negotiate(message):
        try:
            answer = await voice_hub.offer(
                pid, generation, VoiceOfferRequest.model_validate(message["data"])
            )
            if _socket_owners.get(pid) is owner:
                await send(
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
            if _socket_owners.get(pid) is owner:
                try:
                    await send(
                        {
                            "type": "error",
                            "error": exc.code
                            if isinstance(exc, AppError)
                            else "MEDIA_UNAVAILABLE",
                            "message": exc.message
                            if isinstance(exc, AppError)
                            else "Voice negotiation failed; leave and rejoin",
                            "request_id": message.get("request_id"),
                        }
                    )
                except (WebSocketDisconnect, RuntimeError, TimeoutError):
                    pass

    await websocket.accept()
    try:
        raw = await asyncio.wait_for(socket_text(websocket), timeout=10)
        if raw is None:
            return
        if len(raw.encode("utf-8")) > 8192:
            await websocket.close(code=1009)
            return
        first = json.loads(raw)
        if (
            not isinstance(first, dict)
            or first.get("type") != "auth"
            or not isinstance(first.get("token"), str)
        ):
            await websocket.close(code=1008)
            return
        protocol = first.get("protocol_version", 1)
        if type(protocol) is not int or protocol not in (1, 2):
            await websocket.close(code=1008)
            return
        token = first["token"]
        try:
            player = await run_in_threadpool(AuthService(db).authenticate, token)
            pid = player.id
            _socket_owners[pid] = owner
            generation = runtime.attach(pid)
        except AppError:
            pass
        reply = await run_in_threadpool(
            socket_step, db, token, {"type": "enter"}, protocol, generation
        )
        await send(reply)
        if reply.get("type") == "error":
            await websocket.close(code=1008)
            return
        while True:
            if _socket_owners.get(pid) is not owner:
                await websocket.close(code=1008)
                return
            received = False
            try:
                raw = await asyncio.wait_for(socket_text(websocket), timeout=0.2)
                if raw is None:
                    return
                if len(raw.encode("utf-8")) > (65536 if protocol == 2 else 8192):
                    await websocket.close(code=1009)
                    return
                message = json.loads(raw)
                if not isinstance(message, dict):
                    await websocket.close(code=1008)
                    return
                received = True
            except asyncio.TimeoutError:
                message = {"type": "snapshot"}
            # Recheck after await: replaced sockets cannot mutate their successor.
            if _socket_owners.get(pid) is not owner:
                await websocket.close(code=1008)
                return
            if received:
                limiter.check(f"realtime:{pid}", 60, 1)
                runtime.heartbeat(pid, generation)
            reply = await run_in_threadpool(
                socket_step, db, token, message, protocol, generation
            )
            if _socket_owners.get(pid) is not owner:
                return
            await send(reply)
            if (
                protocol == 2
                and reply.get("type") != "error"
                and message.get("type") == "voice.offer"
            ):
                if not tasks:
                    task = asyncio.create_task(negotiate(message))
                    tasks.add(task)
                    task.add_done_callback(tasks.discard)
                else:
                    await send(
                        {
                            "type": "error",
                            "error": "VOICE_NEGOTIATING",
                            "message": "Voice negotiation is already in progress",
                            "request_id": message.get("request_id"),
                        }
                    )
            if reply.get("status") == 401 or (
                protocol == 1 and reply.get("status") == 403
            ):
                await websocket.close(code=1008)
                return
            await asyncio.sleep(0.05)
    except WebSocketDisconnect:
        return
    except (asyncio.TimeoutError, ValueError, AppError):
        await websocket.close(code=1008)
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        if pid is not None:
            await voice_hub.close_connection(pid, generation)
            runtime.detach(pid, generation)
        if pid is not None and _socket_owners.get(pid) is owner:
            _socket_owners.pop(pid, None)
            await run_in_threadpool(RealtimeService(db).leave, pid)
