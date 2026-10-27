from typing import Literal
from pydantic import BaseModel, Field


class MoveRequest(BaseModel):
    x: float = Field(ge=-100000, le=100000, allow_inf_nan=False)
    y: float = Field(ge=-100000, le=100000, allow_inf_nan=False)
    sequence: int = Field(ge=1, strict=True)


class EnterRequest(BaseModel):
    location: Literal["farm", "social_lobby"] = "farm"
    owner_id: int | None = Field(None, gt=0, strict=True)


class NearbyChatRequest(BaseModel):
    request_id: str | None = Field(
        None, min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$"
    )
    body: str = Field(min_length=1, max_length=500, pattern=r".*\S.*")


class EmoteRequest(BaseModel):
    emote: Literal["wave", "happy", "sad", "dance"]
