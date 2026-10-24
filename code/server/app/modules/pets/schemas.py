from typing import Literal
from pydantic import BaseModel, Field


class PetSelection(BaseModel):
    species: Literal["cat", "dog", "rabbit", "fox", "duck", "red_panda"]


class PetAction(BaseModel):
    action: Literal["rename", "feed", "pet", "accessory", "fetch_start", "fetch_finish"]
    name: str | None = Field(None, min_length=1, max_length=32, pattern=r".*\S.*")
    item_code: str | None = Field(None, min_length=1, max_length=32)
