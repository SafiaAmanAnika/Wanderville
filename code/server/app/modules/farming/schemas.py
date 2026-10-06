from datetime import datetime

from pydantic import BaseModel, Field, computed_field, model_validator


class TileRequest(BaseModel):
    x: int = Field(ge=0, le=32767, strict=True)
    y: int = Field(ge=0, le=32767, strict=True)


class PlantRequest(TileRequest):
    item_code: str = Field(min_length=1, max_length=32)

    @model_validator(mode="before")
    @classmethod
    def legacy_crop_alias(cls, data):
        if isinstance(data, dict) and "crop_type" in data:
            if "item_code" in data and data["item_code"] != data["crop_type"]:
                raise ValueError("item_code and crop_type must agree")
            return {**data, "item_code": data["crop_type"]}
        return data


class PlotRequest(BaseModel):
    plot_id: int = Field(gt=0, strict=True)


class RelocateRequest(TileRequest):
    plot_id: int = Field(gt=0, strict=True)


class FarmTileResponse(BaseModel):
    id: int
    x: int
    y: int
    item_code: str | None
    is_tilled: bool
    growth_progress_seconds: float
    growth_stage: int
    is_watered: bool
    planted_at: datetime | None
    ready: bool
    visual_frame: int | None = None

    @computed_field
    @property
    def crop_type(self) -> str | None:
        return self.item_code

    @computed_field
    @property
    def is_harvested(self) -> bool:
        return self.item_code is None


class FarmGridResponse(BaseModel):
    plots: list[FarmTileResponse]
    player_id: int
    # Which world these plots belong to, and whether they may be changed. The
    # client renders from ``world_id`` and gates its UI on ``read_only``; neither
    # is an authorisation decision, which stays on the server.
    world_id: int
    session_mode: str
    read_only: bool


class PlantResponse(BaseModel):
    plot: FarmTileResponse
    water_remaining: int | None = (
        None  # Client owns bucket water; no invented server balance.
    )


class HarvestResponse(BaseModel):
    plot: FarmTileResponse
    item_code: str
    crop_type: str
    quantity: int
