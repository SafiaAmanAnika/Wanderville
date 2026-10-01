from typing import Literal
from pydantic import BaseModel, Field


class MoveRequest(BaseModel):
    x: float = Field(ge=-100000, le=100000, allow_inf_nan=False)
    y: float = Field(ge=-100000, le=100000, allow_inf_nan=False)
    sequence: int = Field(ge=1, strict=True)


class EnterRequest(BaseModel):
    owner_id: int | None = Field(None, gt=0, strict=True)


class NearbyChatRequest(BaseModel):
    body: str = Field(min_length=1, max_length=500, pattern=r".*\S.*")


class EmoteRequest(BaseModel):
    emote: Literal["wave", "happy", "sad", "dance"]
