from __future__ import annotations

import logging
from dataclasses import dataclass

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"


@dataclass
class GoogleUserInfo:
    google_id: str
    email: str
    email_verified: bool
    name: str
    picture: str | None


def verify_google_id_token(id_token: str) -> GoogleUserInfo:
    resp = httpx.get(
        GOOGLE_TOKENINFO_URL,
        params={"id_token": id_token},
        timeout=10.0,
    )
    if resp.status_code != 200:
        raise ValueError("Invalid or expired Google ID token")

    data = resp.json()
    audience = data.get("aud")
    if settings.google_client_id and audience != settings.google_client_id:
        raise ValueError("Google ID token audience mismatch")

    email = data.get("email")
    if not email:
        raise ValueError("Google token missing email claim")

    return GoogleUserInfo(
        google_id=data.get("sub", ""),
        email=email.lower(),
        email_verified=data.get("email_verified", "false") == "true",
        name=data.get("name", ""),
        picture=data.get("picture"),
    )
