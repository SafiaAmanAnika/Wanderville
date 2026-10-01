from datetime import datetime
from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class WorldEvent(Base):
    __tablename__ = "world_events"
    __table_args__ = (
        CheckConstraint("ends_at > starts_at AND quantity > 0", name="event_values"),
        Index("ix_event_window", "starts_at", "ends_at"),
    )
    code: Mapped[str] = mapped_column(String(64), primary_key=True)
    title: Mapped[str] = mapped_column(String(128))
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    item_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    quantity: Mapped[int] = mapped_column(Integer, server_default="1")


class EventClaim(Base):
    __tablename__ = "event_claims"
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    event_code: Mapped[str] = mapped_column(
        ForeignKey("world_events.code", ondelete="CASCADE"), primary_key=True
    )
