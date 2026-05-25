from __future__ import annotations

from typing import Generic, TypeVar

from pydantic import BaseModel

from app.schemas.player import PlayerPublic
from app.schemas.world import WorldPublic

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


class LoginData(BaseModel):
    token: str
    player: PlayerPublic


class LoginResponse(Envelope[LoginData]):
    pass


WorldResponse = Envelope[WorldPublic]
TileUpdateResponse = Envelope[WorldPublic]
