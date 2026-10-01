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
    func,
    false,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class Friendship(Base):
    __tablename__ = "friendships"
    __table_args__ = (
        CheckConstraint("low_id < high_id", name="canonical_pair"),
        CheckConstraint(
            "requested_by = low_id OR requested_by = high_id",
            name="request_participant",
        ),
        CheckConstraint("status IN ('pending','accepted')", name="status"),
        Index("ix_friend_high_status", "high_id", "status"),
    )
    low_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    high_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    requested_by: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE")
    )
    status: Mapped[str] = mapped_column(String(16), server_default="pending")


class PlayerBlock(Base):
    __tablename__ = "player_blocks"
    __table_args__ = (
        CheckConstraint("player_id <> blocked_id", name="not_self"),
        Index("ix_block_reverse", "blocked_id", "player_id"),
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    blocked_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )


class Gift(Base):
    __tablename__ = "gifts"
    __table_args__ = (
        CheckConstraint(
            "sender_id <> receiver_id AND quantity > 0", name="gift_values"
        ),
        UniqueConstraint("sender_id", "request_id"),
        Index("ix_gift_mailbox", "receiver_id", "claimed", "id"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    receiver_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE")
    )
    request_id: Mapped[str] = mapped_column(String(64))
    item_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    quantity: Mapped[int] = mapped_column(Integer)
    claimed: Mapped[bool] = mapped_column(Boolean, server_default=false())
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Trade(Base):
    __tablename__ = "trades"
    __table_args__ = (
        CheckConstraint(
            "sender_id <> receiver_id AND offered_quantity > 0 AND wanted_quantity > 0",
            name="trade_values",
        ),
        CheckConstraint(
            "status IN ('pending','accepted','declined','cancelled')", name="status"
        ),
        UniqueConstraint("sender_id", "request_id"),
        Index("ix_trade_receiver_status", "receiver_id", "status", "id"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    sender_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    receiver_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE")
    )
    request_id: Mapped[str] = mapped_column(String(64))
    offered_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    offered_quantity: Mapped[int] = mapped_column(Integer)
    wanted_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    wanted_quantity: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(16), server_default="pending")


class Invite(Base):
    __tablename__ = "social_invites"
    __table_args__ = (
        CheckConstraint("sender_id <> receiver_id", name="not_self"),
        Index("ix_invite_receiver_expiry", "receiver_id", "expires_at"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    sender_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    receiver_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE")
    )
    world_id: Mapped[int] = mapped_column(
        ForeignKey("player_worlds.id", ondelete="CASCADE")
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    accepted: Mapped[bool] = mapped_column(Boolean, server_default=false())


class DirectMessage(Base):
    __tablename__ = "direct_messages"
    __table_args__ = (
        CheckConstraint("sender_id <> receiver_id", name="not_self"),
        Index("ix_dm_inbox", "receiver_id", "id"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    sender_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    receiver_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE")
    )
    body: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class PlayerReport(Base):
    __tablename__ = "player_reports"
    __table_args__ = (CheckConstraint("reporter_id <> reported_id", name="not_self"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    reporter_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    reported_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    reason: Mapped[str] = mapped_column(String(32))
    details: Mapped[str] = mapped_column(String(1000))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
