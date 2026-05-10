from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict


class PlayerPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    display_name: str
    created_at: datetime
    is_active: bool
