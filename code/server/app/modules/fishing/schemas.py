from pydantic import BaseModel, Field


class CastRequest(BaseModel):
    spot_code: str = Field(min_length=1, max_length=32)
    rod_code: str = Field(min_length=1, max_length=32)


class CatchRequest(BaseModel):
    cast_id: str = Field(min_length=1, max_length=64)
