from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class FarmPlot(Base):
    __tablename__ = "farm_plots"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    x: Mapped[int] = mapped_column(Integer, nullable=False)
    y: Mapped[int] = mapped_column(Integer, nullable=False)
    item_code: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("item_definitions.item_code"),
        nullable=True,
    )
    planted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    growth_stage: Mapped[int] = mapped_column(Integer, default=0)
    is_watered: Mapped[bool] = mapped_column(Boolean, default=False)
    is_harvested: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    player = relationship("Player", back_populates="farm_plots")
    item = relationship("ItemDefinition", lazy="joined")

    MAX_STAGES = 3

    def is_ready_for_harvest(self) -> bool:
        return self.growth_stage >= self.MAX_STAGES and not self.is_harvested

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "x": self.x,
            "y": self.y,
            "item_code": self.item_code,
            "growth_stage": self.growth_stage,
            "is_watered": self.is_watered,
            "is_harvested": self.is_harvested,
            "planted_at": self.planted_at.isoformat() if self.planted_at else None,
            "ready": self.is_ready_for_harvest(),
        }