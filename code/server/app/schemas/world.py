from __future__ import annotations

from datetime import datetime

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
    # tile_type is intentionally a plain string (not an enum).
    # The tile catalog is not yet finalized; an enum will be added
    # when farming/building systems define the canonical set.
    tile_type: str = Field(min_length=1, max_length=64)
