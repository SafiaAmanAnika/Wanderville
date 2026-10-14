from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator


class PreferencesRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    voice_privacy: Literal["off", "friends", "nearby"] | None = None
    wishlist_visibility: Literal["private", "friends"] | None = None
    proximity_prompts: bool | None = Field(None, strict=True)

    @model_validator(mode="after")
    def no_explicit_nulls(self):
        if any(getattr(self, key) is None for key in self.model_fields_set):
            raise ValueError("Preferences cannot be null")
        return self


class WishlistRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    quantity: int = Field(1, ge=1, le=99, strict=True)
    priority: int = Field(0, ge=0, le=10, strict=True)
    expected_version: int = Field(0, ge=0, strict=True)
