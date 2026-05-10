from __future__ import annotations

from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.player import Player
from app.services import auth_service


def _get_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail={"success": False, "error": "NOT_AUTHENTICATED", "message": "Missing Authorization header"},
        )
    prefix = "Bearer "
    if not authorization.startswith(prefix):
        raise HTTPException(
            status_code=401,
            detail={"success": False, "error": "NOT_AUTHENTICATED", "message": "Invalid Authorization header"},
        )
    return authorization[len(prefix) :].strip()


def get_current_player(
    db: Session = Depends(get_db),
    authorization: str | None = Header(default=None),
) -> Player:
    token = _get_bearer_token(authorization)
    try:
        player_id = auth_service.decode_access_token(token)
    except auth_service.AuthError as e:
        raise HTTPException(
            status_code=e.status_code,
            detail={"success": False, "error": e.error, "message": e.message},
        )
    player = db.get(Player, player_id)
    if player is None:
        raise HTTPException(
            status_code=401,
            detail={"success": False, "error": "INVALID_TOKEN", "message": "Invalid or expired token"},
        )
    if not player.is_active:
        raise HTTPException(
            status_code=403,
            detail={"success": False, "error": "INACTIVE_ACCOUNT", "message": "Account is inactive"},
        )
    return player
