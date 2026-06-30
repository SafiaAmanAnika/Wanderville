from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class InventoryItem(Base):
    __tablename__ = "inventory_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    item_code: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("item_definitions.item_code"),
        nullable=False,
    )
    quantity: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    slot_index: Mapped[int] = mapped_column(Integer, nullable=True)
    location: Mapped[str] = mapped_column(String(16), default="inventory", nullable=False)

    created_at: Mapped[datetime] = mapped_column(default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        UniqueConstraint("player_id", "item_code", "location", name="uix_player_item_location"),
        Index("ix_inventory_player_location", "player_id", "location"),
    )

    item = relationship("ItemDefinition", lazy="joined")
    player = relationship("Player", back_populates="inventory_items")