from __future__ import annotations

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps.auth import get_current_player
from app.models.player import Player
from app.schemas.auth import LoginRequest, SignupRequest
from app.schemas.player import PlayerPublic
from app.services import auth_service


router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup")
def signup(payload: SignupRequest, db: Session = Depends(get_db)):
    try:
        player = auth_service.signup(
            db,
            username=payload.username,
            password=payload.password,
            display_name=payload.display_name,
        )
    except auth_service.AuthError as e:
        return JSONResponse(
            status_code=e.status_code,
            content={"success": False, "error": e.error, "message": e.message},
        )

    return {
        "success": True,
        "data": PlayerPublic.model_validate(player).model_dump(),
        "message": "Signup successful",
    }


@router.post("/login")
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    try:
        token, player = auth_service.login(db, username=payload.username, password=payload.password)
    except auth_service.AuthError as e:
        return JSONResponse(
            status_code=e.status_code,
            content={"success": False, "error": e.error, "message": e.message},
        )

    return {
        "success": True,
        "data": {
            "token": token,
            "player": PlayerPublic.model_validate(player).model_dump(),
        },
        "message": "Login successful",
    }


@router.get("/me")
def me(player: Player = Depends(get_current_player)):
    return {
        "success": True,
        "data": PlayerPublic.model_validate(player).model_dump(),
        "message": "OK",
    }
