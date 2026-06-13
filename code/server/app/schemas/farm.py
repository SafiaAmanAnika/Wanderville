from pydantic import BaseModel, Field
from typing import Optional, List


class PlantRequest(BaseModel):
    x: int = Field(..., ge=0, description="Grid X coordinate")
    y: int = Field(..., ge=0, description="Grid Y coordinate")
    crop_type: str = Field(..., min_length=1, max_length=32, description="Crop type: wheat, corn, cotton, tulip, paddy")


class WaterRequest(BaseModel):
    plot_id: int = Field(..., gt=0, description="Farm plot ID to water")


class HarvestRequest(BaseModel):
    plot_id: int = Field(..., gt=0, description="Farm plot ID to harvest")


class FarmPlotResponse(BaseModel):
    id: int
    x: int
    y: int
    crop_type: Optional[str]
    growth_stage: int
    is_watered: bool
    is_harvested: bool
    planted_at: Optional[str]
    ready: bool


class FarmGridResponse(BaseModel):
    plots: List[FarmPlotResponse]
    player_id: int


class PlantResponseData(BaseModel):
    plot: FarmPlotResponse
    water_remaining: int


class HarvestResponseData(BaseModel):
    plot: FarmPlotResponse
    crop_type: str
    quantity: int
