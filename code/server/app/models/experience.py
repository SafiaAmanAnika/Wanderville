from __future__ import annotations

from sqlalchemy import ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class PlayerExperience(Base):
    __tablename__ = "player_experience"

    player_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="CASCADE"),
        primary_key=True,
    )
    current_xp: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_xp: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    level: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    xp_to_next_level: Mapped[int] = mapped_column(Integer, default=100, nullable=False)
    title: Mapped[str] = mapped_column(String(64), nullable=True)

    player = relationship("Player", back_populates="experience")