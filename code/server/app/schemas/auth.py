from __future__ import annotations

from pydantic import BaseModel, Field

from app.schemas.player import PlayerPublic


class SignupRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=6, max_length=128)
    display_name: str = Field(min_length=1, max_length=64)


class LoginRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=6, max_length=128)


class LoginData(BaseModel):
    token: str
    player: PlayerPublic
