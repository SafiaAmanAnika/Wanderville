from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, computed_field, model_validator


class ItemRequest(BaseModel):
    confirmed: bool = False
    item_code: str = Field(min_length=1, max_length=32)
    quantity: int = Field(1, gt=0, le=1_000_000, strict=True)
    location: Literal["inventory"] = "inventory"

    @model_validator(mode="before")
    @classmethod
    def legacy_item_alias(cls, data):
        if isinstance(data, dict) and "item_type" in data:
            if "item_code" in data and data["item_code"] != data["item_type"]:
                raise ValueError("item_code and item_type must agree")
            return {**data, "item_code": data["item_type"]}
        return data


class TransferRequest(ItemRequest):
    to_player_username: str = Field(min_length=3, max_length=32)


class ItemDefinitionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    item_code: str
    name: str
    category: str
    max_stack: int
    sell_value: int
    buy_value: int | None
    growth_time_seconds: int | None
    season: str
    xp_reward: int
    rarity: str
    tradable: bool
    giftable: bool
    usable: bool
    placeable: bool
    icon_path: str | None
    description: str | None


class InventoryItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    player_id: int
    item_code: str
    quantity: int
    slot_index: int | None
    location: str
    created_at: datetime
    updated_at: datetime
    item: ItemDefinitionResponse

    @computed_field
    @property
    def item_type(self) -> str:
        """Deprecated output alias for older backend tools."""
        return self.item_code


class InventoryListResponse(BaseModel):
    items: list[InventoryItemResponse]
    total_items: int
    total_quantity: int
