from typing import Annotated
from pydantic import BaseModel, ConfigDict, Field


class VoiceStateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_id: str = Field(min_length=36, max_length=36)
    muted: bool = Field(True, strict=True)
    deafened: bool = Field(False, strict=True)
    muted_players: list[Annotated[int, Field(gt=0, strict=True)]] = Field(
        default_factory=list, max_length=200
    )


class VoiceOfferRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_id: str = Field(min_length=36, max_length=36)
    sdp: str = Field(min_length=1, max_length=60000)


class DismissRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    target_id: int = Field(gt=0, strict=True)
