from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    UniqueConstraint,
    false,
    true,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.db.timestamps import Timestamps


class FarmTile(Timestamps, Base):
    __tablename__ = "farm_tiles"
    __table_args__ = (
        UniqueConstraint("world_id", "x", "y"),
        CheckConstraint("x >= 0 AND y >= 0", name="nonnegative_coordinates"),
        CheckConstraint("growth_progress_seconds >= 0", name="nonnegative_progress"),
        CheckConstraint("growth_stage BETWEEN 0 AND 3", name="growth_stage"),
        CheckConstraint(
            "NOT is_watered OR watered_at IS NOT NULL", name="water_timestamp"
        ),
        CheckConstraint(
            "(crop_item_code IS NOT NULL AND is_tilled AND planted_at IS NOT NULL AND last_growth_update_at IS NOT NULL) OR (crop_item_code IS NULL AND planted_at IS NULL AND growth_progress_seconds = 0 AND growth_stage = 0 AND NOT is_watered AND watered_at IS NULL AND last_growth_update_at IS NULL)",
            name="crop_state",
        ),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    world_id: Mapped[int] = mapped_column(
        ForeignKey("player_worlds.id", ondelete="CASCADE"), index=True
    )
    x: Mapped[int] = mapped_column(Integer)
    y: Mapped[int] = mapped_column(Integer)
    is_tilled: Mapped[bool] = mapped_column(Boolean, server_default=true())
    crop_item_code: Mapped[str | None] = mapped_column(
        ForeignKey("item_definitions.item_code"), index=True
    )
    planted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    growth_progress_seconds: Mapped[float] = mapped_column(Float, server_default="0")
    growth_stage: Mapped[int] = mapped_column(Integer, server_default="0")
    last_growth_update_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    is_watered: Mapped[bool] = mapped_column(Boolean, server_default=false())
    watered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    item = relationship("ItemDefinition", lazy="selectin")
