from datetime import datetime
from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class PlayerPet(Base):
    __tablename__ = "player_pets"
    __table_args__ = (
        CheckConstraint("affection BETWEEN 0 AND 100", name="affection_range"),
    )
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    species: Mapped[str] = mapped_column(String(32), server_default="cat")
    name: Mapped[str] = mapped_column(String(32), server_default="Mochi")
    affection: Mapped[int] = mapped_column(Integer, server_default="0")
    accessory_code: Mapped[str | None] = mapped_column(
        ForeignKey("item_definitions.item_code")
    )
    last_interaction_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    fetch_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
