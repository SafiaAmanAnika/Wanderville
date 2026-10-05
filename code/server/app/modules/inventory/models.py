from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    false,
    func,
    true,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.db.timestamps import Timestamps

from datetime import datetime


class ItemDefinition(Base):
    __tablename__ = "item_definitions"
    __table_args__ = (
        CheckConstraint("max_stack > 0", name="positive_stack"),
        CheckConstraint("sell_value >= 0", name="nonnegative_sell"),
        CheckConstraint("buy_value IS NULL OR buy_value >= 0", name="nonnegative_buy"),
        CheckConstraint(
            "growth_time_seconds IS NULL OR growth_time_seconds > 0",
            name="positive_growth",
        ),
        CheckConstraint("xp_reward >= 0", name="nonnegative_xp"),
        CheckConstraint("harvest_xp >= 0", name="nonnegative_harvest_xp"),
        CheckConstraint(
            "season IN ('all', 'spring', 'summer', 'autumn', 'winter')", name="season"
        ),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    item_code: Mapped[str] = mapped_column(String(32), unique=True)
    name: Mapped[str] = mapped_column(String(64))
    category: Mapped[str] = mapped_column(String(32), index=True)
    max_stack: Mapped[int] = mapped_column(Integer, server_default="99")
    sell_value: Mapped[int] = mapped_column(Integer, server_default="0")
    buy_value: Mapped[int | None] = mapped_column(Integer)
    growth_time_seconds: Mapped[int | None] = mapped_column(Integer)
    season: Mapped[str] = mapped_column(String(16), server_default="all", index=True)
    xp_reward: Mapped[int] = mapped_column(Integer, server_default="0")
    # One base harvest category only; tags never combine two XP values. NULL
    # means the item is never harvested (seeds, rods, pet items).
    harvest_category: Mapped[str | None] = mapped_column(String(16))
    harvest_xp: Mapped[int] = mapped_column(Integer, server_default="0")
    rarity: Mapped[str] = mapped_column(String(16), server_default="common")
    tradable: Mapped[bool] = mapped_column(Boolean, server_default=true())
    giftable: Mapped[bool] = mapped_column(Boolean, server_default=true())
    usable: Mapped[bool] = mapped_column(Boolean, server_default=false())
    placeable: Mapped[bool] = mapped_column(Boolean, server_default=false())
    icon_path: Mapped[str | None] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(String(512))


class InventoryItem(Timestamps, Base):
    __tablename__ = "inventory_items"
    __table_args__ = (
        UniqueConstraint(
            "player_id",
            "item_code",
            "location",
            "stack_no",
            name="uq_inventory_items_player_stack",
        ),
        CheckConstraint("quantity > 0", name="positive_quantity"),
        CheckConstraint("location = 'inventory'", name="supported_location"),
        CheckConstraint(
            "slot_index IS NULL OR slot_index >= 0", name="nonnegative_slot"
        ),
        CheckConstraint("stack_no >= 0", name="nonnegative_stack"),
        Index("ix_inventory_player_location", "player_id", "location"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    item_code: Mapped[str] = mapped_column(
        ForeignKey("item_definitions.item_code"), index=True
    )
    quantity: Mapped[int] = mapped_column(Integer)
    stack_no: Mapped[int] = mapped_column(Integer, server_default="0")
    slot_index: Mapped[int | None] = mapped_column(Integer)
    location: Mapped[str] = mapped_column(String(16), server_default="inventory")
    item = relationship("ItemDefinition", lazy="selectin")


class PlayerFirstHarvest(Base):
    """One row per (player, crop) so the bonus can be granted exactly once."""

    __tablename__ = "player_first_harvests"
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    item_code: Mapped[str] = mapped_column(
        ForeignKey("item_definitions.item_code"), primary_key=True
    )
    harvested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
