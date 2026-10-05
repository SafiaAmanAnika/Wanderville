from pydantic import BaseModel, Field
from app.modules.inventory.schemas import ItemRequest


class PurchaseRequest(BaseModel):
    request_id: str = Field(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    item_code: str = Field(min_length=1, max_length=32)
    quantity: int = Field(1, ge=1, le=99, strict=True)


class SaleRequest(ItemRequest):
    # Older API callers remain compatible; the store always supplies this key.
    request_id: str | None = Field(None, min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
