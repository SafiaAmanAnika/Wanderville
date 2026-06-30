from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class TilesBulkUpdate(BaseModel):
    tiles: dict


class WorldPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    owner_id: int
    name: str
    tiles: dict
    created_at: datetime


class TileUpdate(BaseModel):
    x: int
    y: int
    tile_type: str = Field(min_length=1, max_length=64)


class WorldStateResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    current_season: str
    season_start_time: Optional[datetime] = None
    season_duration_minutes: int
    day_night_cycle_minutes: int
    current_time_of_day: float
    is_raining: bool