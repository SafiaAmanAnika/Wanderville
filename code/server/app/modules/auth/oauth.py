from dataclasses import dataclass
from functools import lru_cache
import logging
import re

import requests
from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import Request
from google.oauth2 import id_token

from app.core.config import settings
from app.core.exceptions import AppError

logger = logging.getLogger(__name__)

# Bounded tolerance for small differences between the host and Google clocks.
GOOGLE_CLOCK_SKEW_SECONDS = 30


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


# google-auth quotes the token it failed on in some messages (for example
# "Wrong number of segments in token: b'...'"), so exception text is scrubbed
# of token-shaped runs before it can ever reach a log sink.
_TOKEN_SHAPED = re.compile(r"[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}")
_REASON_LIMIT = 200


def diagnostic_reason(exc, raw):
    """Return google-auth's own wording for a rejection, safe to log.

    Only the exception's text is reported. The token, the authorization code,
    the client secret, the nonce and every claim value are left out: the raw
    token is removed verbatim, any remaining token-shaped run is masked, and
    the result is length-capped. google-auth names the failure precisely
    enough to act on ("Token expired", "Token used too early", "Token has
    wrong audience", "Could not verify token signature", "Certificate for key
    id ... not found"), so the reason survives without the credential.
    """
    text = " ".join(str(exc).split())
    for secret in (raw, settings.google_client_id):
        if secret:
            text = text.replace(secret, "<redacted>")
    text = _TOKEN_SHAPED.sub("<redacted>", text)
    return text[:_REASON_LIMIT]


def verify_google(raw, expected_nonce=None):
    if not settings.google_client_id:
        raise AppError("GOOGLE_NOT_CONFIGURED", "Google sign-in is not configured", 503)
    try:
        claims = id_token.verify_oauth2_token(
            raw, google_request(), settings.google_client_id,
            clock_skew_in_seconds=GOOGLE_CLOCK_SKEW_SECONDS,
        )
    except ValueError as exc:
        # Reached for every claim-level rejection google-auth reports as a
        # ValueError (expiry, clock skew, audience, signature, key id). Logging
        # the type and scrubbed reason is what separates those causes; the
        # client still only ever sees the generic message.
        logger.warning(
            "Google identity token rejected: %s: %s",
            type(exc).__name__,
            diagnostic_reason(exc, raw),
        )
        reason = str(exc).lower()
        message = "Google sign-in could not be verified. Start Google sign-in again."
        if "used too early" in reason or "issued in the future" in reason:
            message = "The hosting server clock is behind Google. Enable automatic date/time on the host, then retry."
        elif "expired" in reason:
            message = "Google sign-in expired, or the hosting server clock is ahead. Check automatic date/time and start sign-in again."
        elif "audience" in reason:
            message = "Google sign-in client IDs do not match. The host must check its Google Desktop app configuration."
        raise AppError("INVALID_GOOGLE_TOKEN", message, 401) from exc
    except (GoogleAuthError, requests.RequestException) as exc:
        logger.warning(
            "Google identity token could not be verified: %s: %s",
            type(exc).__name__,
            diagnostic_reason(exc, raw),
        )
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
