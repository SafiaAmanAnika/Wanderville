from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


class AddItemRequest(BaseModel):
    item_type: str = Field(..., min_length=1, max_length=32)
    quantity: int = Field(1, ge=1)


class RemoveItemRequest(BaseModel):
    item_type: str = Field(..., min_length=1, max_length=32)
    quantity: int = Field(1, ge=1)


class TransferItemRequest(BaseModel):
    to_player_username: str = Field(..., min_length=1, max_length=32)
    item_type: str = Field(..., min_length=1, max_length=32)
    quantity: int = Field(1, ge=1)


class InventoryItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    player_id: int
    item_type: str
    quantity: int
    slot_index: Optional[int] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class InventoryListResponse(BaseModel):
    items: List[InventoryItemResponse]
    total_items: int
    total_quantity: int
