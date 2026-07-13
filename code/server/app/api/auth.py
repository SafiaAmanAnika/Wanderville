from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps.auth import get_current_player
from app.deps.rate_limit import _check_rate_limit
from app.models.player import Player
from app.schemas.auth import (
    ChangePasswordRequest,
    ForgotPasswordRequest,
    GoogleAuthRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    ResetPasswordRequest,
    SignupRequest,
)
from app.schemas.player import PlayerPublic
from app.schemas.responses import LoginResponse, PlayerMeResponse, RefreshResponse, SignupResponse
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _error_response(status_code: int, error: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"success": False, "error": error, "message": message},
    )


@router.post("/signup", response_model=SignupResponse)
def signup(payload: SignupRequest, request: Request, db: Session = Depends(get_db)):
    _check_rate_limit(request, max_requests=5)
    try:
        player = auth_service.signup(
            db,
            username=payload.username,
            email=payload.email,
            password=payload.password,
            display_name=payload.display_name,
        )
    except auth_service.AuthError as e:
        return _error_response(e.status_code, e.error, e.message)

    return {
        "success": True,
        "data": PlayerPublic.model_validate(player).model_dump(),
        "message": "Signup successful. Please check your email to verify your account.",
    }


@router.post("/login", response_model=LoginResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)):
    _check_rate_limit(request, max_requests=10)
    try:
        access_token, refresh_token, player = auth_service.login(
            db,
            username=payload.username,
            password=payload.password,
            ip_address=_client_ip(request),
        )
    except auth_service.AuthError as e:
        return _error_response(e.status_code, e.error, e.message)

    return {
        "success": True,
        "data": {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "player": PlayerPublic.model_validate(player).model_dump(),
        },
        "message": "Login successful",
    }


@router.post("/google", response_model=LoginResponse)
def google_auth(payload: GoogleAuthRequest, request: Request, db: Session = Depends(get_db)):
    _check_rate_limit(request, max_requests=10)
    try:
        from app.services.oauth_service import verify_google_id_token

        google_user = verify_google_id_token(payload.id_token)
        access_token, refresh_token, player = auth_service.google_login(
            db,
            google_id=google_user.google_id,
            email=google_user.email,
            email_verified=google_user.email_verified,
            name=google_user.name,
            picture=google_user.picture,
            ip_address=_client_ip(request),
        )
    except auth_service.AuthError as e:
        return _error_response(e.status_code, e.error, e.message)
    except ValueError as e:
        return _error_response(401, "INVALID_GOOGLE_TOKEN", str(e))

    return {
        "success": True,
        "data": {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "player": PlayerPublic.model_validate(player).model_dump(),
        },
        "message": "Google authentication successful",
    }


@router.post("/refresh", response_model=RefreshResponse)
def refresh_token(payload: RefreshRequest, db: Session = Depends(get_db)):
    try:
        player_id, new_refresh_raw = auth_service.rotate_refresh_token(db, payload.refresh_token)
        access_token = auth_service.create_access_token(player_id=player_id)
    except auth_service.AuthError as e:
        return _error_response(e.status_code, e.error, e.message)

    return {
        "success": True,
        "data": {
            "access_token": access_token,
            "refresh_token": new_refresh_raw,
            "token_type": "bearer",
        },
        "message": "Token refreshed",
    }


@router.post("/logout")
def logout(payload: LogoutRequest, db: Session = Depends(get_db)):
    auth_service.revoke_refresh_token(db, payload.refresh_token)
    return {"success": True, "data": None, "message": "Logged out"}


@router.get("/verify-email")
def verify_email(token: str, db: Session = Depends(get_db)):
    try:
        player = auth_service.verify_email(db, token=token)
    except auth_service.AuthError as e:
        return _error_response(e.status_code, e.error, e.message)

    return {
        "success": True,
        "data": PlayerPublic.model_validate(player).model_dump(),
        "message": "Email verified successfully",
    }


@router.post("/resend-verification")
def resend_verification(payload: ForgotPasswordRequest, request: Request, db: Session = Depends(get_db)):
    _check_rate_limit(request, max_requests=3)
    auth_service.resend_verification_email(db, email=payload.email)
    return {
        "success": True,
        "data": None,
        "message": "If that email is registered and unverified, a new verification email has been sent.",
    }


@router.post("/forgot-password")
def forgot_password(payload: ForgotPasswordRequest, request: Request, db: Session = Depends(get_db)):
    _check_rate_limit(request, max_requests=3)
    auth_service.request_password_reset(db, email=payload.email)
    return {"success": True, "data": None, "message": "If that email is registered, a password reset link has been sent."}


@router.post("/reset-password")
def reset_password(payload: ResetPasswordRequest, request: Request, db: Session = Depends(get_db)):
    _check_rate_limit(request, max_requests=5)
    try:
        auth_service.reset_password(db, token=payload.token, new_password=payload.new_password)
    except auth_service.AuthError as e:
        return _error_response(e.status_code, e.error, e.message)

    return {"success": True, "data": None, "message": "Password reset successful. Please log in with your new password."}


@router.put("/change-password")
def change_password(
    payload: ChangePasswordRequest,
    player: Player = Depends(get_current_player),
    db: Session = Depends(get_db),
):
    try:
        auth_service.change_password(
            db,
            player=player,
            current_password=payload.current_password,
            new_password=payload.new_password,
        )
    except auth_service.AuthError as e:
        return _error_response(e.status_code, e.error, e.message)

    return {"success": True, "data": None, "message": "Password changed. All other sessions have been logged out."}


@router.get("/me", response_model=PlayerMeResponse)
def me(player: Player = Depends(get_current_player)):
    return {
        "success": True,
        "data": PlayerPublic.model_validate(player).model_dump(),
        "message": "OK",
    }
