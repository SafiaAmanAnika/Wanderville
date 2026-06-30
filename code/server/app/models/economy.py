from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class PlayerEconomy(Base):
    __tablename__ = "player_economy"

    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        primary_key=True,
    )
    taka_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    coin_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_earned: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_spent: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    player = relationship("Player", back_populates="economy")