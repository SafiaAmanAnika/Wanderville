from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps.auth import get_current_player
from app.deps.rate_limit import _RATE_LIMIT_DISABLED, rate_limiter
from app.models.player import Player
from app.schemas.auth import LoginRequest, SignupRequest
from app.schemas.player import PlayerPublic
from app.schemas.responses import LoginResponse, PlayerMeResponse, SignupResponse
from app.services import auth_service


router = APIRouter(prefix="/auth", tags=["auth"])


def _check_rate_limit(request: Request, max_requests: int) -> None:
    """Raise HTTP 429 if the client IP has exceeded the rate limit."""
    if _RATE_LIMIT_DISABLED:
        return
    client_ip = request.client.host if request.client else "unknown"
    key = f"{request.url.path}:{client_ip}"
    if not rate_limiter.is_allowed(key, max_requests, 60):
        raise HTTPException(
            status_code=429,
            detail={
                "success": False,
                "error": "RATE_LIMITED",
                "message": f"Too many requests. Limit: {max_requests} per 60s",
            },
        )


@router.post("/signup", response_model=SignupResponse)
def signup(payload: SignupRequest, request: Request, db: Session = Depends(get_db)):
    """Register a new player account. No authentication required."""
    _check_rate_limit(request, max_requests=5)
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


@router.post("/login", response_model=LoginResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)):
    """Authenticate a player and return a JWT access token. No authentication required."""
    _check_rate_limit(request, max_requests=10)
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


@router.get("/me", response_model=PlayerMeResponse)
def me(player: Player = Depends(get_current_player)):
    """Return the authenticated player's profile. Requires valid JWT token."""
    return {
        "success": True,
        "data": PlayerPublic.model_validate(player).model_dump(),
        "message": "OK",
    }
