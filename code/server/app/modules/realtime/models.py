from datetime import datetime
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class Presence(Base):
    __tablename__ = "player_presence"
    __table_args__ = (
        Index("ix_presence_room_time", "room", "updated_at"),
        CheckConstraint("sequence >= 0", name="sequence"),
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    room: Mapped[str] = mapped_column(String(64))
    x: Mapped[float] = mapped_column(Float)
    y: Mapped[float] = mapped_column(Float)
    sequence: Mapped[int] = mapped_column(Integer, server_default="0")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    emote: Mapped[str | None] = mapped_column(String(16))
    emote_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class NearbyMessage(Base):
    __tablename__ = "nearby_messages"
    __table_args__ = (Index("ix_nearby_expiry", "expires_at"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    body: Mapped[str] = mapped_column(String(500))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class MessageRecipient(Base):
    __tablename__ = "nearby_message_recipients"
    message_id: Mapped[int] = mapped_column(
        ForeignKey("nearby_messages.id", ondelete="CASCADE"), primary_key=True
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True, index=True
    )
