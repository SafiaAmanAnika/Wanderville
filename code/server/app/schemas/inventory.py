from __future__ import annotations

from datetime import datetime
from typing import Annotated, List, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


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


class _ItemTypeRequest(BaseModel):
    @model_validator(mode="before")
    @classmethod
    def _normalize_item_type(cls, data):
        if isinstance(data, dict) and "item_type" not in data and "item_code" in data:
            data = {**data, "item_type": data["item_code"]}
        return data


class AddItemRequest(_ItemTypeRequest):
    item_type: Annotated[str, Field(min_length=1, max_length=32)]
    quantity: int = Field(1, ge=1)
    location: str = Field("inventory", min_length=1, max_length=16)


class RemoveItemRequest(_ItemTypeRequest):
    item_type: Annotated[str, Field(min_length=1, max_length=32)]
    quantity: int = Field(1, ge=1)


class UseItemRequest(_ItemTypeRequest):
    item_type: Annotated[str, Field(min_length=1, max_length=32)]
    quantity: int = Field(1, ge=1)


class TransferItemRequest(_ItemTypeRequest):
    to_player_username: str = Field(..., min_length=1, max_length=32)
    item_type: Annotated[str, Field(min_length=1, max_length=32)]
    quantity: int = Field(1, ge=1)


class InventoryItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    player_id: int
    item_type: str
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