from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class EconomyResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    player_id: int
    taka_balance: int
    coin_balance: int
    total_earned: int
    total_spent: int


class TransactionRequest(BaseModel):
    amount: int
    currency_type: str = "taka"  # "taka" or "coin"
    description: Optional[str] = None


class XPResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    player_id: int
    current_xp: int
    total_xp: int
    level: int
    xp_to_next_level: int
    title: Optional[str] = None


class XPGainRequest(BaseModel):
    xp_amount: int
    source: Optional[str] = None