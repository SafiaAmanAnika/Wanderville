from datetime import datetime

from pydantic import BaseModel, ConfigDict


class PlayerPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    username: str
    display_name: str
    email: str | None
    email_verified: bool
    avatar_url: str | None
    oauth_provider: str | None
    created_at: datetime
    is_active: bool
    # Deprecated response-only placeholders; position was never synchronized.
    position_x: int = 0
    position_y: int = 0
