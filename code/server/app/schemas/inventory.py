from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


class ItemDefinitionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    item_code: str
    name: str
    category: str
    max_stack: int
    sell_value: int
    buy_value: Optional[int] = None
    growth_time_seconds: Optional[int] = None
    season: str
    xp_reward: int
    rarity: str
    tradable: bool
    giftable: bool
    usable: bool
    placeable: bool
    icon_path: Optional[str] = None
    description: Optional[str] = None


class AddItemRequest(BaseModel):
    item_code: str = Field(..., min_length=1, max_length=32)
    quantity: int = Field(1, ge=1)
    location: str = Field("inventory", min_length=1, max_length=16)


class RemoveItemRequest(BaseModel):
    item_code: str = Field(..., min_length=1, max_length=32)
    quantity: int = Field(1, ge=1)


class UseItemRequest(BaseModel):
    item_code: str = Field(..., min_length=1, max_length=32)
    quantity: int = Field(1, ge=1)


class TransferItemRequest(BaseModel):
    to_player_username: str = Field(..., min_length=1, max_length=32)
    item_code: str = Field(..., min_length=1, max_length=32)
    quantity: int = Field(1, ge=1)


class InventoryItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    player_id: int
    item_code: str
    quantity: int
    slot_index: Optional[int] = None
    location: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    item: Optional[ItemDefinitionResponse] = None


class InventoryListResponse(BaseModel):
    items: List[InventoryItemResponse]
    total_items: int
    total_quantity: int