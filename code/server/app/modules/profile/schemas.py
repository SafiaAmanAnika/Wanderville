from typing import Literal
from pydantic import BaseModel, Field


class ProfileUpdate(BaseModel):
    display_name: str = Field(
        default=None, min_length=1, max_length=64, pattern=r".*\S.*"
    )
    character_code: Literal["catto", "girl", "player1"] = None
    map_code: Literal["campus"] = None
    status_message: str = Field(default=None, max_length=140)
    music_volume: int = Field(default=None, ge=0, le=100, strict=True)
    effects_volume: int = Field(default=None, ge=0, le=100, strict=True)
    fullscreen: bool = None


class TutorialRequest(BaseModel):
    expected_step: int = Field(0, ge=0, le=3, strict=True)
    skip: bool = False


class FeedbackRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000, pattern=r".*\S.*")


class DeleteAccountRequest(BaseModel):
    confirm_username: str = Field(min_length=3, max_length=32)
    password: str | None = Field(None, min_length=1, max_length=128)
    google_id_token: str | None = Field(None, min_length=1, max_length=8192)
