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
    return success(RealtimeService(db).chat(pid, payload.body))


@router.post("/emote")
def emote(
    payload: EmoteRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).emote(pid, payload.emote))


def socket_step(db, token, message):
    from app.modules.auth.service import AuthService
    from app.core.exceptions import AppError
    from fastapi.encoders import jsonable_encoder
    from pydantic import ValidationError

    try:
        player = AuthService(db).authenticate(token)
        service = RealtimeService(db)
        kind = message.get("type", "snapshot")
        if kind == "enter":
            request = EnterRequest.model_validate(message.get("data", {}))
            service.enter(player.id, request.owner_id)
        elif kind == "move":
            service.move(player.id, MoveRequest.model_validate(message.get("data", {})))
        elif kind == "chat":
            service.chat(
                player.id,
                NearbyChatRequest.model_validate(message.get("data", {})).body,
            )
        elif kind == "emote":
            service.emote(
                player.id, EmoteRequest.model_validate(message.get("data", {})).emote
            )
        elif kind != "snapshot":
            raise AppError("INVALID_MESSAGE", "Unknown realtime message type")
        return jsonable_encoder(
            {"type": "snapshot", "data": service.snapshot(player.id)}
        )
    except AppError as exc:
        return {
            "type": "error",
            "error": exc.code,
            "message": exc.message,
            "status": exc.status,
        }
    except ValidationError:
        return {
            "type": "error",
            "error": "VALIDATION_ERROR",
            "message": "Invalid realtime payload",
            "status": 422,
        }
    finally:
        # Read-only snapshots must release connections between frames.
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
        token = first["token"]
        reply = await run_in_threadpool(socket_step, db, token, {"type": "enter"})
        await websocket.send_json(reply)
        if reply.get("type") == "error":
            await websocket.close(code=1008)
            return
        while True:
            try:
                raw = await asyncio.wait_for(socket_text(websocket), timeout=0.2)
                if raw is None:
                    return
                if len(raw.encode("utf-8")) > 8192:
                    await websocket.close(code=1009)
                    return
                message = json.loads(raw)
                if not isinstance(message, dict):
                    await websocket.close(code=1008)
                    return
            except asyncio.TimeoutError:
                message = {"type": "snapshot"}
            reply = await run_in_threadpool(socket_step, db, token, message)
            await websocket.send_json(reply)
            if reply.get("status") in (401, 403):
                await websocket.close(code=1008)
                return
            await asyncio.sleep(0.05)
    except WebSocketDisconnect:
        return
    except (asyncio.TimeoutError, ValueError):
        await websocket.close(code=1008)
