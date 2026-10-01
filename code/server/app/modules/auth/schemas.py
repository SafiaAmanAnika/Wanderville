import re

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.modules.auth.email_validation import is_disposable_email
from app.modules.auth.security import validate_password
from app.modules.players.schemas import PlayerPublic


class SignupRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    email: EmailStr = Field(max_length=255)
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = Field(None, min_length=1, max_length=64)

    @field_validator("username")
    @classmethod
    def valid_username(cls, value):
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", value):
            raise ValueError(
                "Username can only contain letters, numbers, underscores and hyphens"
            )
        return value

    @field_validator("email")
    @classmethod
    def valid_email(cls, value):
        value = value.lower()
        if is_disposable_email(value):
            raise ValueError("Disposable email addresses are not allowed")
        return value

    @field_validator("password")
    @classmethod
    def strong_password(cls, value):
        return validate_password(value)


class LoginRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1, max_length=512)


class GoogleRequest(BaseModel):
    id_token: str = Field(min_length=1, max_length=8192)


class EmailRequest(BaseModel):
    email: EmailStr = Field(max_length=255)

    @field_validator("email")
    @classmethod
    def normalize(cls, value):
        return value.lower()


class NewPassword(BaseModel):
    new_password: str = Field(min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def strong_password(cls, value):
        return validate_password(value)


class ResetRequest(NewPassword):
    token: str = Field(min_length=1, max_length=512)


class ChangePasswordRequest(NewPassword):
    current_password: str = Field(min_length=1, max_length=128)


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class LoginResponse(TokenResponse):
    player: PlayerPublic
