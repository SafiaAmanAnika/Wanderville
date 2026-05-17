from __future__ import annotations

from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.player import Player
from app.services import auth_service

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_current_player(
    db: Session = Depends(get_db),
    token: str = Depends(oauth2_scheme),
) -> Player:
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


def get_current_player_id(player: Player = Depends(get_current_player)) -> int:
    return player.id


def check_owner(resource_owner_id: int, current_user_id: int) -> None:
    if resource_owner_id != current_user_id:
        raise HTTPException(
            status_code=403,
            detail={"success": False, "error": "FORBIDDEN", "message": "You do not own this resource"},
        )
