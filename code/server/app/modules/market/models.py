from datetime import datetime
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base

class PlayerShop(Base):
    __tablename__ = "player_shops"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), unique=True)   # one shop each
    option_id: Mapped[str] = mapped_column(String(32))               # "shop_option_07"
    side: Mapped[str] = mapped_column(String(5))                     # "left" | "right"
    name: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    __table_args__ = (CheckConstraint("side IN ('left','right')", name="side"),)


class ShopListing(Base):
    __tablename__ = "shop_listings"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("player_shops.id", ondelete="CASCADE"))
    item_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    quantity: Mapped[int] = mapped_column(Integer)
    price: Mapped[int] = mapped_column(Integer)
    __table_args__ = (Index("player_shop_listing_unique", "shop_id", "item_code", unique=True),
                      CheckConstraint("quantity >= 0", name="qty"),
                      CheckConstraint("price > 0", name="price"))


class ShopSale(Base):
    __tablename__ = "player_shop_sales"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("player_shops.id", ondelete="CASCADE"))
    buyer_id: Mapped[int] = mapped_column(ForeignKey("players.id"))
    item_code: Mapped[str] = mapped_column(String(64))
    quantity: Mapped[int] = mapped_column(Integer)
    price: Mapped[int] = mapped_column(Integer)
    sold_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())