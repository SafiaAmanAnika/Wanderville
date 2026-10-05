import base64
import logging
import os
import smtplib
import ssl
import threading
import time
import requests
from email.message import EmailMessage
from uuid import uuid4

from app.core.config import SERVER_ROOT, settings

logger = logging.getLogger(__name__)

GMAIL_SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send"
GMAIL_SEND_URL = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"
GMAIL_TOKEN_URL = "https://oauth2.googleapis.com/token"
# Refreshed slightly early so a token cannot expire mid-request.
_TOKEN_EXPIRY_MARGIN_SECONDS = 60

_token_lock = threading.Lock()
_token_state = {"access_token": "", "expires_at": 0.0}


def reset_gmail_token_cache():
    with _token_lock:
        _token_state["access_token"] = ""
        _token_state["expires_at"] = 0.0


def _gmail_access_token():
    """Exchange the stored refresh token for a short-lived send-only token."""
    with _token_lock:
        cached = _token_state["access_token"]
        if cached and time.monotonic() < _token_state["expires_at"]:
            return cached
        response = requests.post(
            GMAIL_TOKEN_URL,
            data={
                "client_id": settings.gmail_client_id,
                "client_secret": settings.gmail_client_secret,
                "refresh_token": settings.gmail_refresh_token,
                "grant_type": "refresh_token",
            },
            timeout=10,
        )
        response.raise_for_status()
        payload = response.json()
        token = payload.get("access_token")
        if not isinstance(token, str) or not token:
            raise ValueError("Gmail token response contained no access token")
        _token_state["access_token"] = token
        _token_state["expires_at"] = time.monotonic() + float(
            payload.get("expires_in", 3600)
        ) - _TOKEN_EXPIRY_MARGIN_SECONDS
        return token


def _send_via_gmail_api(message):
    raw = base64.urlsafe_b64encode(message.as_bytes()).decode("ascii")
    response = requests.post(
        GMAIL_SEND_URL,
        headers={"Authorization": f"Bearer {_gmail_access_token()}"},
        json={"raw": raw},
        timeout=10,
    )
    response.raise_for_status()


def send_account_email(address, username, raw_token, kind):
    """Called after commit. Tests replace this function; tokens never enter logs."""
    message = EmailMessage()
    sender = (
        settings.gmail_sender_email
        if settings.email_delivery == "gmail_api"
        else settings.email_from
    )
    message["From"], message["To"] = sender, address
    if kind == "email_verification":
        message["Subject"] = "Verify your WanderVille account"
        text = f"Hi {username},\nOpen {settings.email_base_url.rstrip('/')}/auth/verify-email?token={raw_token}\nThis link expires in {settings.email_verification_expire_minutes} minutes."
    else:
        message["Subject"] = "Reset your WanderVille password"
        text = f"Hi {username},\nOpen {settings.email_base_url.rstrip('/')}/auth/reset-password?token={raw_token}\nExpires in {settings.password_reset_expire_minutes} minutes."
    message.set_content(text)
    if settings.email_delivery == "file" or (
        settings.email_delivery == "auto" and settings.is_development
    ):
        directory = SERVER_ROOT / ".dev-mail"
        directory.mkdir(mode=0o700, exist_ok=True)
        path = directory / f"{uuid4().hex}.eml"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as output:
            output.write(message.as_bytes())
        logger.info("Development email saved to the private .dev-mail directory")
        return
    if settings.email_delivery == "brevo":
        response = requests.post(
            "https://api.brevo.com/v3/smtp/email",
            headers={"api-key": settings.brevo_api_key},
            json={
                "sender": {"email": settings.email_from, "name": "WanderVille"},
                "to": [{"email": address}],
                "subject": str(message["Subject"]),
                "textContent": text,
            },
            timeout=10,
        )
        response.raise_for_status()
        return
    if settings.email_delivery == "gmail_api":
        _send_via_gmail_api(message)
        return
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
        if settings.smtp_starttls:
            smtp.starttls(context=ssl.create_default_context())
        if settings.smtp_user:
            smtp.login(settings.smtp_user, settings.smtp_password)
        smtp.send_message(message)


def deliver_safely(*args):
    try:
        send_account_email(*args)
        return True
    except (OSError, ValueError, smtplib.SMTPException, requests.RequestException):
        # Email is external to the database transaction. Resend can retry delivery.
        # Keep forgot/reset responses indistinguishable for registered addresses.
        logger.error("Account email delivery failed; retry with the resend endpoint")
        return False
