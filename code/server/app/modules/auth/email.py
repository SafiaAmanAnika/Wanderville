import logging
import os
import smtplib
import ssl
from email.message import EmailMessage
from uuid import uuid4

from app.core.config import SERVER_ROOT, settings

logger = logging.getLogger(__name__)


def send_account_email(address, username, raw_token, kind):
    """Called after commit. Tests replace this function; tokens never enter logs."""
    message = EmailMessage()
    message["From"], message["To"] = settings.email_from, address
    if kind == "email_verification":
        message["Subject"] = "Verify your WanderVille account"
        text = f"Hi {username},\nOpen {settings.email_base_url.rstrip('/')}/auth/verify-email?token={raw_token}\nThis link expires in {settings.email_verification_expire_minutes} minutes."
    else:
        message["Subject"] = "Reset your WanderVille password"
        text = f"Hi {username},\nOpen the game with wanderville://reset-password?token={raw_token}\nOr submit this token and your new_password to POST /auth/reset-password.\nToken: {raw_token}\nExpires in {settings.password_reset_expire_minutes} minutes."
    message.set_content(text)
    if settings.is_development:
        directory = SERVER_ROOT / ".dev-mail"
        directory.mkdir(mode=0o700, exist_ok=True)
        path = directory / f"{uuid4().hex}.eml"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as output:
            output.write(message.as_bytes())
        logger.info("Development email saved to the private .dev-mail directory")
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
    except (OSError, smtplib.SMTPException):
        # Email is external to the database transaction. Resend can retry delivery.
        # Keep forgot/reset responses indistinguishable for registered addresses.
        logger.error("Account email delivery failed; retry with the resend endpoint")
