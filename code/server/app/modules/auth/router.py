from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.core.rate_limit import rate_limit
from app.core.responses import Envelope, success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player, get_current_player_id
from app.modules.auth.schemas import (
    ChangePasswordRequest,
    EmailRequest,
    GoogleRequest,
    GoogleCodeRequest,
    LoginRequest,
    LoginResponse,
    RefreshRequest,
    ResetRequest,
    SignupRequest,
    TokenResponse,
)
from app.modules.auth.service import AuthService
from app.modules.players.schemas import PlayerPublic

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/config")
def auth_config():
    from app.core.config import settings

    local_mail = settings.email_delivery == "file" or (
        settings.email_delivery == "auto" and settings.is_development
    )
    # Clients only distinguish local file mail from real remote delivery.
    delivery = (
        "file"
        if local_mail
        else settings.email_delivery
        if settings.email_delivery in {"brevo", "gmail_api"}
        else "smtp"
    )
    return success(
        {"google_client_id": settings.google_client_id, "email_delivery": delivery}
    )


@router.post("/google/code", response_model=Envelope[LoginResponse], dependencies=[Depends(rate_limit(10))])
def google_code(payload: GoogleCodeRequest, request: Request, db: Session = Depends(get_db)):
    from app.modules.auth.oauth import exchange_code

    return success(AuthService(db).google_login(
        exchange_code(payload), request.client.host if request.client else None, payload.nonce
    ), "Google authentication successful")


@router.post(
    "/signup",
    response_model=Envelope[PlayerPublic],
    dependencies=[Depends(rate_limit(5))],
)
def signup(payload: SignupRequest, db: Session = Depends(get_db)):
    return success(
        AuthService(db).signup(payload), "Signup successful. Please verify your email."
    )


@router.post(
    "/login",
    response_model=Envelope[LoginResponse],
    dependencies=[Depends(rate_limit(10))],
)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)):
    return success(
        AuthService(db).login(payload, request.client.host if request.client else None),
        "Login successful",
    )


@router.post(
    "/google",
    response_model=Envelope[LoginResponse],
    dependencies=[Depends(rate_limit(10))],
)
def google(payload: GoogleRequest, request: Request, db: Session = Depends(get_db)):
    return success(
        AuthService(db).google_login(
            payload.id_token, request.client.host if request.client else None
        ),
        "Google authentication successful",
    )


@router.post(
    "/refresh",
    response_model=Envelope[TokenResponse],
    dependencies=[Depends(rate_limit(20))],
)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    return success(AuthService(db).refresh(payload.refresh_token), "Token refreshed")


@router.post(
    "/logout", response_model=Envelope[None], dependencies=[Depends(rate_limit(20))]
)
def logout(payload: RefreshRequest, db: Session = Depends(get_db)):
    AuthService(db).logout(payload.refresh_token)
    return success(message="Logged out")


@router.get(
    "/verify-email",
    response_model=Envelope[PlayerPublic],
    dependencies=[Depends(rate_limit(10))],
)
def verify_email(
    request: Request,
    token: str = Query(min_length=1, max_length=512), db: Session = Depends(get_db)
):
    from app.core.exceptions import AppError
    from app.modules.auth.pages import account_page

    browser = "text/html" in request.headers.get("accept", "")
    try:
        player = AuthService(db).verify_email(token)
    except AppError as exc:
        if browser:
            return account_page("Email verification", exc.message)
        raise
    if browser:
        return account_page("Email verified", "Your account is ready. Return to Wanderville and log in.")
    return success(player, "Email verified successfully")


@router.get("/reset-password", include_in_schema=False)
def reset_password_page():
    from app.modules.auth.pages import reset_page

    return reset_page()


@router.post(
    "/resend-verification",
    response_model=Envelope[None],
    dependencies=[Depends(rate_limit(3))],
)
def resend(payload: EmailRequest, db: Session = Depends(get_db)):
    AuthService(db).request_email(payload.email, "email_verification")
    return success(
        message="Verification email requested. If the address is registered and unverified, check its inbox."
    )


@router.post(
    "/forgot-password",
    response_model=Envelope[None],
    dependencies=[Depends(rate_limit(3))],
)
def forgot(payload: EmailRequest, db: Session = Depends(get_db)):
    AuthService(db).request_email(payload.email, "password_reset")
    return success(
        message="Password reset requested. If the address is eligible, check its inbox."
    )


@router.post(
    "/reset-password",
    response_model=Envelope[None],
    dependencies=[Depends(rate_limit(5))],
)
def reset(payload: ResetRequest, db: Session = Depends(get_db)):
    AuthService(db).reset_password(payload)
    return success(message="Password reset successful. Please log in again.")


@router.put(
    "/change-password",
    response_model=Envelope[None],
    dependencies=[Depends(rate_limit(5))],
)
def change(
    payload: ChangePasswordRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    AuthService(db).change_password(player_id, payload)
    return success(message="Password changed. All sessions have been logged out.")


@router.get("/me", response_model=Envelope[PlayerPublic])
def me(player=Depends(get_current_player)):
    return success(PlayerPublic.model_validate(player))
