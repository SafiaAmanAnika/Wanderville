from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class WorldPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    owner_id: int
    name: str
    created_at: datetime
    updated_at: datetime
    tiles: dict = Field(
        default_factory=dict
    )  # Deprecated, response-only compatibility field.


class WorldStateResponse(BaseModel):
    current_season: Literal["spring", "summer", "autumn", "winter"]
    server_time: datetime
    season_end_time: datetime
    season_start_time: datetime
    season_duration_minutes: int
    day_night_cycle_minutes: int
    current_time_of_day: float
    is_raining: bool
    weather: Literal["clear", "rain", "snow"]
