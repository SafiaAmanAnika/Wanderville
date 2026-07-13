from __future__ import annotations

from typing import Generic, TypeVar

from pydantic import BaseModel

from app.schemas.player import PlayerPublic

T = TypeVar("T")


class Envelope(BaseModel, Generic[T]):
    success: bool
    data: T | None = None
    message: str = ""


class HealthData(BaseModel):
    status: str


class HealthResponse(Envelope[HealthData]):
    pass


SignupResponse = Envelope[PlayerPublic]
PlayerMeResponse = Envelope[PlayerPublic]


class TokenPairData(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    player: PlayerPublic


class LoginResponse(Envelope[TokenPairData]):
    pass


class RefreshData(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshResponse(Envelope[RefreshData]):
    pass


MessageResponse = Envelope[None]


WorldResponse = Envelope[dict]
TileUpdateResponse = Envelope[dict]
