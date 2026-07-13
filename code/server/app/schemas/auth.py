from __future__ import annotations

import re

from pydantic import BaseModel, Field, field_validator

from app.services.email_validation import validate_email_address


_PASSWORD_SPECIAL_RE = re.compile(r"[!@#$%^&*()_+\-=\[\]{};:'\",.<>?/\\|`~]")


def _validate_password_strength(password: str) -> str:
    if len(password) < 8:
        return "Password must be at least 8 characters long"
    if not re.search(r"[A-Z]", password):
        return "Password must contain at least one uppercase letter"
    if not re.search(r"[a-z]", password):
        return "Password must contain at least one lowercase letter"
    if not re.search(r"\d", password):
        return "Password must contain at least one digit"
    if not _PASSWORD_SPECIAL_RE.search(password):
        return "Password must contain at least one special character"
    return ""


class SignupRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    email: str = Field(max_length=255)
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=64)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        error = validate_email_address(v)
        if error:
            raise ValueError(error)
        return v.strip().lower()

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        if not re.match(r"^[a-zA-Z0-9_-]+$", v):
            raise ValueError("Username can only contain letters, numbers, underscores, and hyphens")
        return v

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        error = _validate_password_strength(v)
        if error:
            raise ValueError(error)
        return v


class LoginRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class GoogleAuthRequest(BaseModel):
    id_token: str = Field(min_length=1)


class ForgotPasswordRequest(BaseModel):
    email: str = Field(max_length=255)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return v.strip().lower()


class ResetPasswordRequest(BaseModel):
    token: str = Field(min_length=1)
    new_password: str = Field(min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        error = _validate_password_strength(v)
        if error:
            raise ValueError(error)
        return v


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        error = _validate_password_strength(v)
        if error:
            raise ValueError(error)
        return v
