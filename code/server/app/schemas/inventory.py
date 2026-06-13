from pydantic import BaseModel, Field
from typing import Optional, List


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
    id: int
    player_id: int
    item_type: str
    quantity: int
    slot_index: Optional[int]
    created_at: Optional[str]
    updated_at: Optional[str]


class InventoryListResponse(BaseModel):
    items: List[InventoryItemResponse]
    total_items: int
    total_quantity: int
