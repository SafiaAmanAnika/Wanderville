from typing import Literal
from pydantic import BaseModel, Field


class TargetRequest(BaseModel):
    target_id: int = Field(gt=0, strict=True)


class FriendAction(BaseModel):
    action: Literal["accept", "decline", "remove"]


class TradeAction(BaseModel):
    action: Literal["accept", "decline", "cancel"]


class GiftRequest(TargetRequest):
    request_id: str = Field(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    item_code: str = Field(min_length=1, max_length=32)
    quantity: int = Field(1, ge=1, le=99, strict=True)


class TradeRequest(TargetRequest):
    request_id: str = Field(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    offered_code: str = Field(min_length=1, max_length=32)
    offered_quantity: int = Field(1, ge=1, le=99, strict=True)
    wanted_code: str = Field(min_length=1, max_length=32)
    wanted_quantity: int = Field(1, ge=1, le=99, strict=True)


class MessageRequest(TargetRequest):
    body: str = Field(min_length=1, max_length=500, pattern=r".*\S.*")


class ReportRequest(TargetRequest):
    reason: Literal["harassment", "cheating", "spam", "other"]
    details: str = Field("", max_length=1000)
