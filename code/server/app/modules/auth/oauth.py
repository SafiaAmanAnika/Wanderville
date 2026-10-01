from dataclasses import dataclass
from functools import lru_cache

import requests
from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import Request
from google.oauth2 import id_token

from app.core.config import settings
from app.core.exceptions import AppError


@dataclass(frozen=True)
class GoogleIdentity:
    subject: str
    email: str
    name: str
    picture: str | None
    authoritative_email: bool


@lru_cache(maxsize=1)
def google_request():
    # A reused HTTP session permits connection reuse. Signature/claim verification
    # is delegated to Google's library, never the debug tokeninfo endpoint.
    return Request(session=requests.Session())


def verify_google(raw):
    if not settings.google_client_id:
        raise AppError("GOOGLE_NOT_CONFIGURED", "Google sign-in is not configured", 503)
    try:
        claims = id_token.verify_oauth2_token(
            raw, google_request(), settings.google_client_id
        )
    except ValueError as exc:
        raise AppError(
            "INVALID_GOOGLE_TOKEN", "Invalid or expired Google token", 401
        ) from exc
    except (GoogleAuthError, requests.RequestException) as exc:
        raise AppError(
            "GOOGLE_UNAVAILABLE", "Google sign-in is temporarily unavailable", 503
        ) from exc
    if (
        not claims.get("sub")
        or not claims.get("email")
        or claims.get("email_verified") is not True
    ):
        raise AppError(
            "INVALID_GOOGLE_TOKEN", "Google token must include a verified email", 401
        )
    email = claims["email"].lower()
    return GoogleIdentity(
        claims["sub"],
        email,
        claims.get("name", "")[:64],
        claims.get("picture"),
        email.endswith("@gmail.com") or bool(claims.get("hd")),
    )
