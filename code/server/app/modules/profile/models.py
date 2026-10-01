from datetime import datetime
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    func,
    false,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class PlayerProfile(Base):
    __tablename__ = "player_profiles"
    __table_args__ = (
        CheckConstraint("water_charges BETWEEN 0 AND 20", name="water_capacity"),
        CheckConstraint(
            "music_volume BETWEEN 0 AND 100 AND effects_volume BETWEEN 0 AND 100",
            name="volume_range",
        ),
        CheckConstraint("tutorial_step BETWEEN 0 AND 3", name="tutorial_range"),
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    character_code: Mapped[str | None] = mapped_column(String(32))
    map_code: Mapped[str] = mapped_column(String(32), server_default="campus")
    status_message: Mapped[str] = mapped_column(String(140), server_default=text("''"))
    water_charges: Mapped[int] = mapped_column(Integer, server_default="20")
    music_volume: Mapped[int] = mapped_column(Integer, server_default="100")
    effects_volume: Mapped[int] = mapped_column(Integer, server_default="100")
    fullscreen: Mapped[bool] = mapped_column(Boolean, server_default=false())
    tutorial_step: Mapped[int] = mapped_column(Integer, server_default="0")
    last_seen_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), index=True
    )
    last_saved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class EncounterHint(Base):
    __tablename__ = "encounter_hints"
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    feature: Mapped[str] = mapped_column(String(32), primary_key=True)


class Feedback(Base):
    __tablename__ = "feedback"
    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    message: Mapped[str] = mapped_column(String(2000))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
