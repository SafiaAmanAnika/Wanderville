from sqlalchemy import CheckConstraint, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class HouseTier(Base):
    __tablename__ = "house_tiers"
    __table_args__ = (
        CheckConstraint(
            "tier >= 1 AND cost >= 0 AND required_level >= 1", name="tier_values"
        ),
    )
    tier: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(64))
    cost: Mapped[int] = mapped_column(Integer)
    required_level: Mapped[int] = mapped_column(Integer, server_default="1")


class PlayerHouse(Base):
    __tablename__ = "player_houses"
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    tier: Mapped[int] = mapped_column(
        ForeignKey("house_tiers.tier"), server_default="1"
    )


class Decoration(Base):
    __tablename__ = "decorations"
    __table_args__ = (
        UniqueConstraint("player_id", "x", "y"),
        CheckConstraint(
            "x BETWEEN 0 AND 32767 AND y BETWEEN 0 AND 32767", name="coordinates"
        ),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    item_code: Mapped[str] = mapped_column(ForeignKey("item_definitions.item_code"))
    x: Mapped[int] = mapped_column(Integer)
    y: Mapped[int] = mapped_column(Integer)
