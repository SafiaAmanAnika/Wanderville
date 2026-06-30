from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class World(Base):
    __tablename__ = "worlds"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(64), nullable=False, default="My World")
    tiles: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    owner = relationship("Player", back_populates="world")


class WorldState(Base):
    __tablename__ = "world_state"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    current_season: Mapped[str] = mapped_column(String(16), default="summer", nullable=False)
    season_start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    season_duration_minutes: Mapped[int] = mapped_column(Integer, default=10080, nullable=False)
    day_night_cycle_minutes: Mapped[int] = mapped_column(Integer, default=40, nullable=False)
    current_time_of_day: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    is_raining: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    last_updated: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )