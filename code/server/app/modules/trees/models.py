from datetime import datetime
from sqlalchemy import CheckConstraint, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class CutTree(Base):
    """A map tree (geometry.json "trees") this player has chopped down.

    Each player has their own forest, so a cut tree is gone only for them.
    """

    __tablename__ = "player_cut_trees"
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    tree_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    cut_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SpawnedTree(Base):
    """A tree grown for one player after they cleared a season's forest."""

    __tablename__ = "player_spawned_trees"
    __table_args__ = (
        CheckConstraint(
            "season IN ('summer','autumn','winter','spring')", name="season"
        ),
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    player_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    season: Mapped[str] = mapped_column(String(8))
    scene: Mapped[str] = mapped_column(String(128))
    # Where the trunk meets the ground, in world coordinates, like geometry.json.
    x: Mapped[float] = mapped_column(Float)
    y: Mapped[float] = mapped_column(Float)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
