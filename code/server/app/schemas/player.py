from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict


class PlayerPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    display_name: str
    email: str | None = None
    email_verified: bool = False
    avatar_url: str | None = None
    oauth_provider: str | None = None
    created_at: datetime
    is_active: bool
    position_x: int
    position_y: int
