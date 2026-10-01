import hashlib
import re
import secrets
from datetime import timedelta

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from jose import JWTError, jwt

from app.core.clock import utcnow
from app.core.config import settings
from app.core.exceptions import InvalidToken

hasher = PasswordHasher()


def validate_password(password):
    if not 8 <= len(password) <= 128 or not all(
        re.search(pattern, password)
        for pattern in (r"[A-Z]", r"[a-z]", r"\d", r"[^\w\s]|_")
    ):
        raise ValueError(
            "Password needs 8-128 characters, uppercase, lowercase, a digit and a special character"
        )
    return password


def hash_password(password):
    return hasher.hash(validate_password(password))


def verify_password(password, password_hash):
    try:
        return bool(password_hash) and hasher.verify(password_hash, password)
    except (VerificationError, InvalidHashError):
        return False


def hash_token(raw):
    return hashlib.sha256(raw.encode()).hexdigest()


def new_token():
    return secrets.token_urlsafe(48)


def create_access_token(player_id, token_version=0):
    now = utcnow()
    return jwt.encode(
        {
            "sub": str(player_id),
            "type": "access",
            "ver": token_version,
            "jti": secrets.token_hex(16),
            "iat": now,
            "exp": now + timedelta(minutes=settings.access_token_expire_minutes),
        },
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )


def decode_access_token(raw):
    try:
        data = jwt.decode(
            raw,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
            options={
                "require_exp": True,
                "require_iat": True,
                "require_sub": True,
                "require_jti": True,
            },
        )
        if (
            data.get("type") != "access"
            or type(data.get("ver")) is not int
            or int(data["sub"]) < 1
        ):
            raise InvalidToken()
        return int(data["sub"]), data["ver"]
    except (JWTError, ValueError, TypeError, KeyError) as exc:
        raise InvalidToken() from exc
