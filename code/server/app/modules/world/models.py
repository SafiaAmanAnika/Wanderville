from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.clock import utcnow
from app.db.base import Base
from app.db.timestamps import Timestamps


class PlayerWorld(Timestamps, Base):
    __tablename__ = "player_worlds"
    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), unique=True
    )
    name: Mapped[str] = mapped_column(String(64), server_default="My World")
    owner = relationship("Player", back_populates="world")
    farm_tiles = relationship(
        "FarmTile", cascade="all, delete-orphan", passive_deletes=True
    )


class WorldState(Base):
    __tablename__ = "world_state"
    __table_args__ = (
        CheckConstraint("id = 1", name="singleton"),
        CheckConstraint(
            "current_season IN ('spring', 'summer', 'autumn', 'winter')", name="season"
        ),
        CheckConstraint("weather IN ('clear', 'rain', 'snow')", name="weather"),
        CheckConstraint("season_duration_minutes > 0", name="positive_season_duration"),
        CheckConstraint("day_night_cycle_minutes > 0", name="positive_day_duration"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    current_season: Mapped[str] = mapped_column(String(16), server_default="summer")
    season_started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    season_duration_minutes: Mapped[int] = mapped_column(
        Integer, server_default="10080"
    )
    weather: Mapped[str] = mapped_column(String(16), server_default="clear")
    day_cycle_anchor_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    day_night_cycle_minutes: Mapped[int] = mapped_column(Integer, server_default="40")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=utcnow
    )
