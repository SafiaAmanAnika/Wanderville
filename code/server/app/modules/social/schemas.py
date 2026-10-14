from typing import Literal
from pydantic import BaseModel, Field, model_validator


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
    wishlist_entry_id: int | None = Field(None, gt=0, strict=True)
    wishlist_version: int | None = Field(None, gt=0, strict=True)

    @model_validator(mode="after")
    def wishlist_link(self):
        if (self.wishlist_entry_id is None) != (self.wishlist_version is None):
            raise ValueError("wishlist_entry_id and wishlist_version are required together")
        return self


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


class FarmInviteRequest(BaseModel):
    """Host names the one guest to invite.

    ``guest_player_id`` and ``target_id`` are accepted as the same field so the
    legacy ``/social/invites`` shape keeps working, but disagreement is
    rejected rather than silently preferring one.
    """

    guest_player_id: int | None = Field(None, gt=0, strict=True)
    target_id: int | None = Field(None, gt=0, strict=True)

    @model_validator(mode="after")
    def single_target(self):
        if (
            self.guest_player_id is None
            and self.target_id is None
        ):
            raise ValueError("guest_player_id is required")
        if (
            self.guest_player_id is not None
            and self.target_id is not None
            and self.guest_player_id != self.target_id
        ):
            raise ValueError("guest_player_id and target_id must agree")
        return self

    @property
    def guest(self) -> int:
        return self.guest_player_id or self.target_id
