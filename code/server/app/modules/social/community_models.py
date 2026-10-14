"""Persistent social preferences and wishlists; gifts remain the item escrow."""

from datetime import datetime
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    true,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class SocialPreferences(Base):
    __tablename__ = "social_preferences"
    __table_args__ = (
        CheckConstraint(
            "voice_privacy IN ('off','friends','nearby')", name="voice_privacy"
        ),
        CheckConstraint(
            "wishlist_visibility IN ('private','friends')", name="wishlist_visibility"
        ),
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    voice_privacy: Mapped[str] = mapped_column(String(16), server_default="friends")
    wishlist_visibility: Mapped[str] = mapped_column(
        String(16), server_default="friends"
    )
    proximity_prompts: Mapped[bool] = mapped_column(Boolean, server_default=true())


class WishlistEntry(Base):
    __tablename__ = "wishlist_entries"
    __table_args__ = (
        UniqueConstraint("player_id", "item_code"),
        CheckConstraint(
            "quantity > 0 AND quantity <= 99 AND priority >= 0 AND priority <= 10 AND version > 0",
            name="values",
        ),
        Index("ix_wishlist_owner_active", "player_id", "active"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    item_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    quantity: Mapped[int] = mapped_column(Integer)
    priority: Mapped[int] = mapped_column(Integer, server_default="0")
    version: Mapped[int] = mapped_column(Integer, server_default="1")
    active: Mapped[bool] = mapped_column(Boolean, server_default=true())


class GiftWishlistAllocation(Base):
    __tablename__ = "gift_wishlist_allocations"
    gift_id: Mapped[int] = mapped_column(
        ForeignKey("gifts.id", ondelete="CASCADE"), primary_key=True
    )
    entry_id: Mapped[int] = mapped_column(ForeignKey("wishlist_entries.id"), index=True)
    expected_version: Mapped[int] = mapped_column(Integer)


class ChatReceipt(Base):
    __tablename__ = "nearby_chat_receipts"
    sender_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    request_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    body_hash: Mapped[str] = mapped_column(String(64))
    # No FK: receipt survives the ten-second message retention period.
    message_id: Mapped[int] = mapped_column(Integer)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class SocialRevision(Base):
    __tablename__ = "social_revisions"
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    revision: Mapped[int] = mapped_column(Integer, server_default="1")
