from datetime import datetime
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    func,
    false,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class ItemRule(Base):
    __tablename__ = "item_rules"
    __table_args__ = (
        CheckConstraint(
            "partition IN ('seeds','crops','fish','rare_materials','tools','houses')",
            name="partition",
        ),
        CheckConstraint("required_level >= 1", name="level"),
    )
    item_code: Mapped[str] = mapped_column(
        ForeignKey("item_definitions.item_code", ondelete="CASCADE"), primary_key=True
    )
    partition: Mapped[str] = mapped_column(String(32))
    required_level: Mapped[int] = mapped_column(Integer, server_default="1")
    harvest_code: Mapped[str | None] = mapped_column(
        ForeignKey("item_definitions.item_code")
    )
    pet_food: Mapped[bool] = mapped_column(Boolean, server_default=false())
    pet_accessory: Mapped[bool] = mapped_column(Boolean, server_default=false())
    fishing_rod: Mapped[bool] = mapped_column(Boolean, server_default=false())


class CollectionEntry(Base):
    __tablename__ = "collection_entries"
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    item_code: Mapped[str] = mapped_column(
        ForeignKey("item_definitions.item_code"), primary_key=True
    )
    first_obtained_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Purchase(Base):
    __tablename__ = "shop_purchases"
    __table_args__ = (
        CheckConstraint("quantity > 0 AND unit_price >= 0", name="purchase_values"),
        Index("ix_purchase_player_day", "player_id", "game_day"),
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    request_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    item_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    quantity: Mapped[int] = mapped_column(Integer)
    unit_price: Mapped[int] = mapped_column(Integer)
    game_day: Mapped[int] = mapped_column(Integer)
