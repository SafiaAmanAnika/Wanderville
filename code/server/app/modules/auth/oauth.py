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


def exchange_code(payload):
    if not settings.google_client_id:
        raise AppError("GOOGLE_NOT_CONFIGURED", "Configure a Google Desktop app client ID on the server", 503)
    values = {
        "client_id": settings.google_client_id,
        "code": payload.code,
        "code_verifier": payload.code_verifier,
        "redirect_uri": payload.redirect_uri,
        "grant_type": "authorization_code",
    }
    if settings.google_client_secret:
        values["client_secret"] = settings.google_client_secret
    try:
        response = requests.post("https://oauth2.googleapis.com/token", data=values, timeout=10)
        response.raise_for_status()
        raw = response.json().get("id_token")
        if not isinstance(raw, str) or not raw:
            raise ValueError("Missing identity token")
        return raw
    except (requests.RequestException, ValueError) as exc:
        raise AppError("GOOGLE_EXCHANGE_FAILED", "Google sign-in could not finish. Check the server's Desktop app credentials and try again.", 401) from exc


def verify_google(raw, expected_nonce=None):
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
    if expected_nonce is not None and claims.get("nonce") != expected_nonce:
        raise AppError("INVALID_GOOGLE_TOKEN", "Google sign-in session does not match", 401)
    email = claims["email"].lower()
    return GoogleIdentity(
        claims["sub"],
        email,
        claims.get("name", "")[:64],
        claims.get("picture"),
        email.endswith("@gmail.com") or bool(claims.get("hd")),
    )
