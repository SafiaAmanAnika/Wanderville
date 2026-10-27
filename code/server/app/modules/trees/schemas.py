from pydantic import BaseModel, Field


class ChopRequest(BaseModel):
    tree_id: str = Field(min_length=1, max_length=64)
    # Positions new trees must keep clear of, such as the player's house, which
    # only the client knows. Used only if this chop clears the season.
    avoid: list[tuple[float, float]] = Field(default_factory=list, max_length=8)
