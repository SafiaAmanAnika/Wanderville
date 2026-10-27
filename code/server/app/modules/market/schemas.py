from typing import Literal
from pydantic import BaseModel, Field

# Match the store UI's steppers. The price column is a 32-bit integer, so an
# unbounded price would fail at the database instead of being refused here.
MAX_QUANTITY = 99
MAX_PRICE = 9999

class OpenShopRequest(BaseModel):
    option_id: str = Field(min_length=1, max_length=32)
    side: Literal["left", "right"]
    name: str = Field(min_length=1, max_length=64)

class ListingRequest(BaseModel):
    item_code: str = Field(min_length=1)
    quantity: int = Field(gt=0, le=MAX_QUANTITY, strict=True)
    price: int = Field(gt=0, le=MAX_PRICE, strict=True)

class BuyRequest(BaseModel):
    shop_id: int = Field(gt=0, strict=True)
    item_code: str
    quantity: int = Field(gt=0, le=MAX_QUANTITY, strict=True)

class UnstockRequest(BaseModel):
    item_code: str = Field(min_length=1)
    quantity: int = Field(gt=0, le=MAX_QUANTITY, strict=True)