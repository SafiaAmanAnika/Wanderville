from typing import Literal
from pydantic import BaseModel, Field

class OpenShopRequest(BaseModel):
    option_id: str = Field(min_length=1, max_length=32)
    side: Literal["left", "right"]
    name: str = Field(min_length=1, max_length=64)

class ListingRequest(BaseModel):
    item_code: str = Field(min_length=1)
    quantity: int = Field(gt=0, strict=True)
    price: int = Field(gt=0, strict=True)

class BuyRequest(BaseModel):
    shop_id: int = Field(gt=0, strict=True)
    item_code: str
    quantity: int = Field(gt=0, strict=True)

class UnstockRequest(BaseModel):
    item_code: str = Field(min_length=1)
    quantity: int = Field(gt=0, strict=True)