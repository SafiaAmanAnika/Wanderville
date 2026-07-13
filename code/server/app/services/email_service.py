from __future__ import annotations

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.config import settings

logger = logging.getLogger(__name__)


def _send_via_smtp(to_email: str, subject: str, html_body: str) -> None:
    msg = MIMEMultipart("alternative")
    msg["From"] = settings.email_from
    msg["To"] = to_email
    msg["Subject"] = subject
    msg.attach(MIMEText(html_body, "html"))

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
        server.starttls()
        server.login(settings.smtp_user, settings.smtp_password)
        server.sendmail(settings.email_from, to_email, msg.as_string())


def send_email(to_email: str, subject: str, html_body: str) -> None:
    if settings.wanderville_env == "dev":
        logger.info(
            "=== EMAIL (dev mode — not sent) ===\n"
            "To: %s\nSubject: %s\nBody:\n%s\n"
            "===================================",
            to_email, subject, html_body,
        )
        return
    try:
        _send_via_smtp(to_email, subject, html_body)
    except Exception:
        logger.exception("Failed to send email to %s", to_email)


def send_verification_email(to_email: str, username: str, token: str) -> None:
    verify_url = f"{settings.email_base_url}/auth/verify-email?token={token}"
    subject = "Verify your Wanderville account"
    html_body = f"""
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #4a7c59;">Welcome to Wanderville!</h2>
        <p>Hi <strong>{username}</strong>,</p>
        <p>Thanks for signing up. Please verify your email address to activate your account:</p>
        <p style="text-align: center; margin: 30px 0;">
            <a href="{verify_url}"
               style="background-color: #4a7c59; color: white; padding: 12px 24px;
                      text-decoration: none; border-radius: 6px; font-weight: bold;">
                Verify Email
            </a>
        </p>
        <p style="color: #666; font-size: 13px;">
            Or copy this link: {verify_url}
        </p>
        <p style="color: #666; font-size: 13px;">
            This link expires in {settings.email_verification_expire_minutes} minutes.
            If you didn't create this account, you can safely ignore this email.
        </p>
    </body>
    </html>
    """
    send_email(to_email, subject, html_body)


def send_password_reset_email(to_email: str, username: str, token: str) -> None:
    reset_url = f"{settings.email_base_url}/auth/reset-password?token={token}"
    subject = "Reset your Wanderville password"
    html_body = f"""
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #4a7c59;">Password Reset Request</h2>
        <p>Hi <strong>{username}</strong>,</p>
        <p>We received a request to reset your password. Click the link below to set a new password:</p>
        <p style="text-align: center; margin: 30px 0;">
            <a href="{reset_url}"
               style="background-color: #4a7c59; color: white; padding: 12px 24px;
                      text-decoration: none; border-radius: 6px; font-weight: bold;">
                Reset Password
            </a>
        </p>
        <p style="color: #666; font-size: 13px;">
            Or copy this link: {reset_url}
        </p>
        <p style="color: #666; font-size: 13px;">
            This link expires in {settings.password_reset_expire_minutes} minutes.
            If you didn't request this, you can safely ignore this email.
        </p>
    </body>
    </html>
    """
    send_email(to_email, subject, html_body)
