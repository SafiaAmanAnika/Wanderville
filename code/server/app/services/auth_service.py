from __future__ import annotations

from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.models.player import Player


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class AuthError(Exception):
    def __init__(self, error: str, message: str, status_code: int = 400):
        self.error = error
        self.message = message
        self.status_code = status_code


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(password: str, hashed_password: str) -> bool:
    return pwd_context.verify(password, hashed_password)


def create_access_token(*, player_id: int) -> str:
    expires = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {
        "sub": str(player_id),
        "exp": expires,
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> int:
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        sub = payload.get("sub")
        if not sub:
            raise AuthError("INVALID_TOKEN", "Token missing subject", status_code=401)
        return int(sub)
    except (ValueError, JWTError):
        raise AuthError("INVALID_TOKEN", "Invalid or expired token", status_code=401)


def signup(db: Session, *, username: str, password: str, display_name: str) -> Player:
    existing = db.execute(select(Player).where(Player.username == username)).scalar_one_or_none()
    if existing is not None:
        raise AuthError("USERNAME_TAKEN", "This username is already taken", status_code=400)

    player = Player(
        username=username,
        hashed_password=hash_password(password),
        display_name=display_name,
        is_active=True,
    )
    db.add(player)
    db.commit()
    db.refresh(player)
    return player


def login(db: Session, *, username: str, password: str) -> tuple[str, Player]:
    player = db.execute(select(Player).where(Player.username == username)).scalar_one_or_none()
    if player is None:
        raise AuthError("INVALID_CREDENTIALS", "Invalid username or password", status_code=401)

    if not verify_password(password, player.hashed_password):
        raise AuthError("INVALID_CREDENTIALS", "Invalid username or password", status_code=401)

    if not player.is_active:
        raise AuthError("INACTIVE_ACCOUNT", "Account is inactive", status_code=403)

    token = create_access_token(player_id=player.id)
    return token, player
