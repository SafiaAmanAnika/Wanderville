from __future__ import annotations

import hashlib
import logging
import re
import secrets
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.config import settings
from app.models.player import Player
from app.models.refresh_token import RefreshToken
from app.services import email_service, world_service
from app.services.email_validation import validate_email_address

logger = logging.getLogger(__name__)

pwd_context = CryptContext(
    schemes=["argon2", "bcrypt"],
    default="argon2",
    deprecated=["bcrypt"],
)

_SPECIAL_CHAR_RE = re.compile(r"[!@#$%^&*()_+\-=\[\]{};:'\",.<>?/\\|`~]")


class AuthError(Exception):
    def __init__(self, error: str, message: str, status_code: int = 400):
        self.error = error
        self.message = message
        self.status_code = status_code


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(password: str, hashed_password: str) -> bool:
    return pwd_context.verify(password, hashed_password)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def create_access_token(*, player_id: int) -> str:
    now = datetime.now(timezone.utc)
    expires = now + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {
        "sub": str(player_id),
        "type": "access",
        "jti": secrets.token_hex(16),
        "exp": expires,
        "iat": now,
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> int:
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "access":
            raise AuthError("INVALID_TOKEN", "Invalid token type", status_code=401)
        sub = payload.get("sub")
        if not sub:
            raise AuthError("INVALID_TOKEN", "Token missing subject", status_code=401)
        return int(sub)
    except (ValueError, JWTError):
        raise AuthError("INVALID_TOKEN", "Invalid or expired token", status_code=401)


def _create_refresh_token_raw() -> tuple[str, str, datetime]:
    raw_token = secrets.token_urlsafe(64)
    token_hashed = hash_token(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_expire_days)
    return raw_token, token_hashed, expires_at


def create_refresh_token(db: Session, *, player_id: int, device_info: str | None = None) -> str:
    raw_token, token_hashed, expires_at = _create_refresh_token_raw()
    db_token = RefreshToken(
        token_hash=token_hashed,
        player_id=player_id,
        device_info=device_info,
        expires_at=expires_at,
        revoked=False,
    )
    db.add(db_token)
    db.commit()
    return raw_token


def _rotate_refresh_token(db: Session, old_token_record: RefreshToken) -> str:
    old_token_record.revoked = True
    raw_token, token_hashed, expires_at = _create_refresh_token_raw()
    new_record = RefreshToken(
        token_hash=token_hashed,
        player_id=old_token_record.player_id,
        device_info=old_token_record.device_info,
        expires_at=expires_at,
        revoked=False,
    )
    db.add(new_record)
    db.commit()
    return raw_token


def validate_refresh_token(db: Session, raw_token: str) -> RefreshToken:
    token_hash = hash_token(raw_token)
    result = db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    ).scalar_one_or_none()

    if result is None:
        raise AuthError("INVALID_REFRESH_TOKEN", "Invalid refresh token", status_code=401)
    if result.revoked:
        raise AuthError("REVOKED_REFRESH_TOKEN", "Refresh token has been revoked", status_code=401)
    if result.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        raise AuthError("EXPIRED_REFRESH_TOKEN", "Refresh token has expired", status_code=401)
    return result


def rotate_refresh_token(db: Session, raw_token: str) -> tuple[str, str]:
    record = validate_refresh_token(db, raw_token)
    new_raw = _rotate_refresh_token(db, record)
    return record.player_id, new_raw


def revoke_refresh_token(db: Session, raw_token: str) -> None:
    token_hash = hash_token(raw_token)
    result = db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    ).scalar_one_or_none()
    if result and not result.revoked:
        result.revoked = True
        db.commit()


def revoke_all_refresh_tokens(db: Session, player_id: int) -> None:
    tokens = db.execute(
        select(RefreshToken).where(
            RefreshToken.player_id == player_id,
            RefreshToken.revoked == False,
        )
    ).scalars().all()
    for t in tokens:
        t.revoked = True
    if tokens:
        db.commit()


def validate_password_strength(password: str) -> str | None:
    if len(password) < 8:
        return "Password must be at least 8 characters long"
    if not re.search(r"[A-Z]", password):
        return "Password must contain at least one uppercase letter"
    if not re.search(r"[a-z]", password):
        return "Password must contain at least one lowercase letter"
    if not re.search(r"\d", password):
        return "Password must contain at least one digit"
    if not _SPECIAL_CHAR_RE.search(password):
        return "Password must contain at least one special character"
    return None


def _is_account_locked(player: Player) -> bool:
    if player.locked_until is None:
        return False
    locked_until = player.locked_until
    if locked_until.tzinfo is None:
        locked_until = locked_until.replace(tzinfo=timezone.utc)
    return locked_until > datetime.now(timezone.utc)


def _record_failed_login(db: Session, player: Player) -> None:
    player.failed_login_attempts += 1
    if player.failed_login_attempts >= settings.max_login_attempts:
        player.locked_until = datetime.now(timezone.utc) + timedelta(minutes=settings.lockout_minutes)
        logger.warning(
            "Account locked: player %d (%s) - too many failed attempts",
            player.id, player.username,
        )
    db.commit()


def _reset_failed_login(db: Session, player: Player) -> None:
    if player.failed_login_attempts > 0 or player.locked_until is not None:
        player.failed_login_attempts = 0
        player.locked_until = None
        db.commit()


def _generate_verification_token() -> str:
    return secrets.token_urlsafe(32)


def signup(
    db: Session,
    *,
    username: str,
    email: str,
    password: str,
    display_name: str | None = None,
) -> Player:
    email = email.strip().lower()

    email_err = validate_email_address(email)
    if email_err:
        raise AuthError("INVALID_EMAIL", email_err, status_code=400)

    password_err = validate_password_strength(password)
    if password_err:
        raise AuthError("WEAK_PASSWORD", password_err, status_code=400)

    existing = db.execute(select(Player).where(Player.username == username)).scalar_one_or_none()
    if existing is not None:
        raise AuthError("USERNAME_TAKEN", "This username is already taken", status_code=400)

    existing_email = db.execute(select(Player).where(Player.email == email)).scalar_one_or_none()
    if existing_email is not None:
        raise AuthError("EMAIL_TAKEN", "An account with this email already exists", status_code=400)

    verification_token = _generate_verification_token()
    verification_expires = datetime.now(timezone.utc) + timedelta(
        minutes=settings.email_verification_expire_minutes
    )

    player = Player(
        username=username,
        email=email,
        hashed_password=hash_password(password),
        display_name=display_name or username,
        is_active=False,
        email_verified=False,
        email_verification_token=hash_token(verification_token),
        email_verification_expires=verification_expires,
    )
    db.add(player)
    db.commit()
    db.refresh(player)

    try:
        world_service.create_world(db, player.id)
    except SQLAlchemyError:
        logger.exception("Failed to auto-create world for player %d during signup", player.id)

    email_service.send_verification_email(email, username, verification_token)
    return player


def login(
    db: Session,
    *,
    username: str,
    password: str,
    ip_address: str | None = None,
) -> tuple[str, str, Player]:
    player = db.execute(select(Player).where(Player.username == username)).scalar_one_or_none()
    if player is None:
        raise AuthError("INVALID_CREDENTIALS", "Invalid username or password", status_code=401)

    if _is_account_locked(player):
        raise AuthError(
            "ACCOUNT_LOCKED",
            f"Account is temporarily locked due to too many failed attempts. "
            f"Try again in {settings.lockout_minutes} minutes.",
            status_code=423,
        )

    if player.hashed_password is None:
        raise AuthError(
            "OAUTH_ONLY_ACCOUNT",
            "This account uses Google Sign-In. Please log in with Google.",
            status_code=401,
        )

    if not verify_password(password, player.hashed_password):
        _record_failed_login(db, player)
        raise AuthError("INVALID_CREDENTIALS", "Invalid username or password", status_code=401)

    if not player.is_active:
        raise AuthError("UNVERIFIED_EMAIL", "Please verify your email before logging in", status_code=403)

    _reset_failed_login(db, player)

    player.last_login_at = datetime.now(timezone.utc)
    player.last_login_ip = ip_address
    db.commit()

    access_token = create_access_token(player_id=player.id)
    refresh_token = create_refresh_token(db, player_id=player.id)
    return access_token, refresh_token, player


def verify_email(db: Session, *, token: str) -> Player:
    token_hashed = hash_token(token)
    player = db.execute(
        select(Player).where(Player.email_verification_token == token_hashed)
    ).scalar_one_or_none()

    if player is None:
        raise AuthError("INVALID_TOKEN", "Invalid or expired verification link", status_code=400)

    if player.email_verification_expires:
        expires = player.email_verification_expires
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
        if expires < datetime.now(timezone.utc):
            raise AuthError("EXPIRED_TOKEN", "Verification link has expired. Please request a new one.", status_code=400)

    player.email_verified = True
    player.is_active = True
    player.email_verification_token = None
    player.email_verification_expires = None
    db.commit()
    db.refresh(player)
    return player


def resend_verification_email(db: Session, *, email: str) -> None:
    email = email.strip().lower()
    player = db.execute(select(Player).where(Player.email == email)).scalar_one_or_none()
    if player is None or player.email_verified:
        return

    verification_token = _generate_verification_token()
    player.email_verification_token = hash_token(verification_token)
    player.email_verification_expires = datetime.now(timezone.utc) + timedelta(
        minutes=settings.email_verification_expire_minutes
    )
    db.commit()
    email_service.send_verification_email(email, player.username, verification_token)


def request_password_reset(db: Session, *, email: str) -> None:
    email = email.strip().lower()
    player = db.execute(select(Player).where(Player.email == email)).scalar_one_or_none()
    if player is None or not player.email_verified:
        return

    reset_token = _generate_verification_token()
    player.password_reset_token = hash_token(reset_token)
    player.password_reset_expires = datetime.now(timezone.utc) + timedelta(
        minutes=settings.password_reset_expire_minutes
    )
    db.commit()
    email_service.send_password_reset_email(email, player.username, reset_token)


def reset_password(db: Session, *, token: str, new_password: str) -> None:
    password_err = validate_password_strength(new_password)
    if password_err:
        raise AuthError("WEAK_PASSWORD", password_err, status_code=400)

    token_hashed = hash_token(token)
    player = db.execute(
        select(Player).where(Player.password_reset_token == token_hashed)
    ).scalar_one_or_none()

    if player is None:
        raise AuthError("INVALID_TOKEN", "Invalid or expired reset link", status_code=400)

    if player.password_reset_expires:
        expires = player.password_reset_expires
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
        if expires < datetime.now(timezone.utc):
            raise AuthError("EXPIRED_TOKEN", "Reset link has expired. Please request a new one.", status_code=400)

    player.hashed_password = hash_password(new_password)
    player.password_reset_token = None
    player.password_reset_expires = None
    player.failed_login_attempts = 0
    player.locked_until = None
    db.commit()

    revoke_all_refresh_tokens(db, player.id)


def change_password(
    db: Session,
    *,
    player: Player,
    current_password: str,
    new_password: str,
) -> None:
    if player.hashed_password is None:
        raise AuthError(
            "OAUTH_ONLY_ACCOUNT",
            "This account uses Google Sign-In. Password change is not available.",
            status_code=400,
        )

    if not verify_password(current_password, player.hashed_password):
        raise AuthError("INVALID_PASSWORD", "Current password is incorrect", status_code=401)

    password_err = validate_password_strength(new_password)
    if password_err:
        raise AuthError("WEAK_PASSWORD", password_err, status_code=400)

    player.hashed_password = hash_password(new_password)
    db.commit()

    revoke_all_refresh_tokens(db, player.id)


def google_login(
    db: Session,
    *,
    google_id: str,
    email: str,
    email_verified: bool,
    name: str,
    picture: str | None,
    ip_address: str | None = None,
) -> tuple[str, str, Player]:
    if not email_verified:
        raise AuthError(
            "GOOGLE_EMAIL_NOT_VERIFIED",
            "Your Google email is not verified",
            status_code=400,
        )

    email = email.strip().lower()

    existing = db.execute(
        select(Player).where(Player.email == email)
    ).scalar_one_or_none()

    if existing is not None:
        if existing.oauth_provider != "google":
            existing.oauth_provider = "google"
            existing.oauth_provider_id = google_id
            if picture and not existing.avatar_url:
                existing.avatar_url = picture
            db.commit()
            db.refresh(existing)

        if not existing.is_active:
            existing.is_active = True
            existing.email_verified = True
            existing.email_verification_token = None
            existing.email_verification_expires = None
            db.commit()
            db.refresh(existing)

        _reset_failed_login(db, existing)
        existing.last_login_at = datetime.now(timezone.utc)
        existing.last_login_ip = ip_address
        db.commit()

        access_token = create_access_token(player_id=existing.id)
        refresh_token = create_refresh_token(db, player_id=existing.id)
        return access_token, refresh_token, existing

    username = email.split("@")[0]
    base_username = re.sub(r"[^a-zA-Z0-9_-]", "", username)[:32]
    if len(base_username) < 3:
        base_username = "player"
    candidate = base_username
    counter = 1
    while db.execute(select(Player).where(Player.username == candidate)).scalar_one_or_none():
        candidate = f"{base_username}{counter}"
        counter += 1

    player = Player(
        username=candidate,
        email=email,
        hashed_password=None,
        display_name=name or candidate,
        is_active=True,
        email_verified=True,
        oauth_provider="google",
        oauth_provider_id=google_id,
        avatar_url=picture,
    )
    db.add(player)
    db.commit()
    db.refresh(player)

    try:
        world_service.create_world(db, player.id)
    except SQLAlchemyError:
        logger.exception("Failed to auto-create world for player %d during Google signup", player.id)

    access_token = create_access_token(player_id=player.id)
    refresh_token = create_refresh_token(db, player_id=player.id)
    return access_token, refresh_token, player
