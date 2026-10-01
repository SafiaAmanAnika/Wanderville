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


class XPResponse(BaseModel):
    player_id: int
    current_xp: int
    total_xp: int
    level: int
    xp_to_next_level: int
    title: str | None = None


class TransactionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    amount: int
    transaction_type: str
    reason: str
    created_at: datetime
