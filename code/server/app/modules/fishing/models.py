from datetime import datetime
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    String,
    false,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class FishingSpot(Base):
    __tablename__ = "fishing_spots"
    code: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(64))
    freezes_in_winter: Mapped[bool] = mapped_column(Boolean, server_default=false())


class FishingSession(Base):
    __tablename__ = "fishing_sessions"
    __table_args__ = (CheckConstraint("expires_at > bite_at", name="bite_window"),)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    cast_id: Mapped[str] = mapped_column(String(64), unique=True)
    spot_code: Mapped[str] = mapped_column(ForeignKey("fishing_spots.code"))
    rod_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    item_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    bite_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    resolved: Mapped[bool] = mapped_column(Boolean, server_default=false())


class GroundDrop(Base):
    __tablename__ = "ground_drops"
    __table_args__ = (Index("ix_ground_owner_expiry", "player_id", "expires_at"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    item_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    spot_code: Mapped[str] = mapped_column(ForeignKey("fishing_spots.code"))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    claimed: Mapped[bool] = mapped_column(Boolean, server_default=false())
