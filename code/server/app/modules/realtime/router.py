"""Realtime HTTP and WebSocket transport.

The routes only bind URLs to services and to the session handler. Message
semantics live in ``protocol.py``, socket lifecycle in ``session.py``, presence
rules in ``service.py``, and voice/lease state in ``runtime.py`` and ``voice.py``.
"""

from fastapi import APIRouter, Depends, WebSocket
from sqlalchemy.orm import Session

from app.core.responses import success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.realtime.schemas import (
    EmoteRequest,
    EnterRequest,
    MoveRequest,
    NearbyChatRequest,
)
from app.modules.realtime.service import RealtimeService
from app.modules.realtime.session import RealtimeSession

router = APIRouter(prefix="/realtime", tags=["realtime"])


@router.post("/enter")
def enter(
    payload: EnterRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).enter(player_id, payload.owner_id))


@router.post("/move")
def move(
    payload: MoveRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).move(player_id, payload))


@router.get("/snapshot")
def snapshot(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(RealtimeService(db).snapshot(player_id))


@router.post("/chat")
def chat(
    payload: NearbyChatRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).chat(player_id, payload.body, payload.request_id))


@router.post("/emote")
def emote(
    payload: EmoteRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(RealtimeService(db).emote(player_id, payload.emote))


@router.get("/proximity")
def proximity(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    from app.modules.realtime.proximity import proximity_view

    return success(proximity_view(db, player_id))


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    await RealtimeSession(websocket, db).run()