from datetime import datetime

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.clock import utcnow
from app.db.base import Base


class PlayerEconomy(Base):
    __tablename__ = "player_economy"
    __table_args__ = tuple(
        CheckConstraint(f"{name} >= 0", name=f"nonnegative_{name}")
        for name in ("aura_balance", "total_earned", "total_spent")
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    aura_balance: Mapped[int] = mapped_column(BigInteger, server_default="0")
    total_earned: Mapped[int] = mapped_column(BigInteger, server_default="0")
    total_spent: Mapped[int] = mapped_column(BigInteger, server_default="0")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=utcnow
    )


class EconomyTransaction(Base):
    __tablename__ = "economy_transactions"
    __table_args__ = (
        CheckConstraint(
            "(transaction_type = 'earn' AND amount > 0) OR (transaction_type = 'spend' AND amount < 0)",
            name="signed_amount",
        ),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    amount: Mapped[int] = mapped_column(BigInteger)
    transaction_type: Mapped[str] = mapped_column(String(16))
    reason: Mapped[str] = mapped_column(String(255))
    reference_type: Mapped[str | None] = mapped_column(String(32))
    reference_id: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )


class PlayerExperience(Base):
    __tablename__ = "player_experience"
    __table_args__ = (
        CheckConstraint("total_xp >= 0", name="nonnegative_xp"),
        CheckConstraint("level >= 1", name="positive_level"),
        CheckConstraint("inventory_base_capacity >= 0", name="nonnegative_inventory_base"),
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    total_xp: Mapped[int] = mapped_column(BigInteger, server_default="0")
    level: Mapped[int] = mapped_column(Integer, server_default="1")
    inventory_base_capacity: Mapped[int] = mapped_column(Integer, server_default="30")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=utcnow
    )


class PlayerLevelReward(Base):
    """Claims log so every level pays out exactly once, even on a replay."""

    __tablename__ = "player_level_rewards"
    __table_args__ = (
        CheckConstraint("level >= 1", name="reward_level"),
        CheckConstraint("aura >= 0", name="reward_aura"),
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    level: Mapped[int] = mapped_column(Integer, primary_key=True)
    aura: Mapped[int] = mapped_column(Integer, server_default="0")
    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
