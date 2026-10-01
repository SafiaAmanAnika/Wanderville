from pydantic import BaseModel, Field


class UpgradeRequest(BaseModel):
    expected_tier: int = Field(ge=1, le=10, strict=True)


class DecorationRequest(BaseModel):
    item_code: str = Field(min_length=1, max_length=32)
    x: int = Field(ge=0, le=32767, strict=True)
    y: int = Field(ge=0, le=32767, strict=True)
