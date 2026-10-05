from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class TransactionRequest(BaseModel):
    amount: int = Field(gt=0, le=1_000_000, strict=True)
    currency_type: Literal["taka", "aura"] = "taka"
    description: str | None = Field(None, max_length=255)


class XPGainRequest(BaseModel):
    xp_amount: int = Field(gt=0, le=1_000_000, strict=True)
    source: str | None = Field(None, max_length=255)


class EconomyResponse(BaseModel):
    player_id: int
    aura_balance: int
    taka_balance: int
    coin_balance: Literal[0] = 0
    total_earned: int
    total_spent: int


class LevelRewardResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    level: int
    aura: int = 0
    title: str


class UnlockedItemResponse(BaseModel):
    item_code: str
    name: str
    required_level: int


class XPResponse(BaseModel):
    player_id: int
    # XP earned inside the current level, and the whole span between floors.
    current_xp: int
    total_xp: int
    level: int
    xp_to_next_level: int
    xp_span: int
    xp_floor: int
    title: str
    max_level: bool
    next_title: str | None = None
    next_title_level: int | None = None
    # Slots the shared inventory pool gains by reaching this level.
    slot_increment: int = 0
    slot_capacity: int = 0
    rewards: list[LevelRewardResponse] = Field(default_factory=list)
    unlocked_items: list[UnlockedItemResponse] = Field(default_factory=list)


class TransactionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    amount: int
    transaction_type: str
    reason: str
    created_at: datetime
