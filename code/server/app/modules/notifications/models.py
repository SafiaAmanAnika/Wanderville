from datetime import datetime
from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    String,
    UniqueConstraint,
    func,
    false,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        Index("ix_notification_inbox", "player_id", "dismissed", "id"),
        UniqueConstraint("player_id", "event_key"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(32))
    message: Mapped[str] = mapped_column(String(512))
    target: Mapped[str | None] = mapped_column(String(128))
    event_key: Mapped[str | None] = mapped_column(String(128))
    is_read: Mapped[bool] = mapped_column(Boolean, server_default=false())
    dismissed: Mapped[bool] = mapped_column(Boolean, server_default=false())
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
