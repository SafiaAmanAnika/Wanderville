from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.clock import utcnow
from app.db.base import Base
from app.db.timestamps import Timestamps

# Where a player stands in the shared map, and therefore where a visitor appears
# unless the host has moved their farm gate. Defined here so the world schema is
# the single source of truth and realtime does not have to import a map value.
CAMPUS_SPAWN = (7377.0, -891.0)

# The shared map's realtime room key. The two room kinds are "campus" (the
# shared, stateless map) and "world:{id}" (a persistent world), so this is the
# only literal that is not derived from a world id. It lives next to
# CAMPUS_SPAWN so no module has to hardcode the string.
CAMPUS_ROOM = "campus"


class PlayerWorld(Timestamps, Base):
    """Exactly one persistent world per player.

    ``uq_player_worlds_owner_id`` is the whole isolation guarantee: no player can
    ever reach another player's farm data through this table, because ownership
    is unique and every farm entity hangs off ``world_id``.
    """

    __tablename__ = "player_worlds"
    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        ForeignKey("players.id", ondelete="CASCADE"), unique=True
    )
    name: Mapped[str] = mapped_column(String(64), server_default="My World")
    # Where a visitor appears when they enter this farm. Visitors never spawn
    # from their own world coordinates, so this defaults to the shared spawn
    # point rather than the map origin.
    farm_entrance_x: Mapped[float] = mapped_column(
        Float, nullable=False, server_default=str(CAMPUS_SPAWN[0])
    )
    farm_entrance_y: Mapped[float] = mapped_column(
        Float, nullable=False, server_default=str(CAMPUS_SPAWN[1])
    )
    # Admission cap, owned and enforced by the host's world row. 5 is the
    # product maximum; 1 lets a host close their farm down without deletion.
    # The 1..5 bound is enforced by the request schema and re-clamped in
    # ``app.modules.world.access.capacity``: it is intentionally not a database
    # CHECK, because adding one would force Alembic to rebuild this table and
    # cascade away every farm_tiles row on SQLite.
    visitor_limit: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="5"
    )
    owner = relationship("Player", back_populates="world")
    farm_tiles = relationship(
        "FarmTile", cascade="all, delete-orphan", passive_deletes=True
    )


class WorldState(Base):
    __tablename__ = "world_state"
    __table_args__ = (
        CheckConstraint("id = 1", name="singleton"),
        CheckConstraint(
            "current_season IN ('spring', 'summer', 'autumn', 'winter')", name="season"
        ),
        CheckConstraint("weather IN ('clear', 'rain', 'snow')", name="weather"),
        CheckConstraint("season_duration_minutes > 0", name="positive_season_duration"),
        CheckConstraint("day_night_cycle_minutes > 0", name="positive_day_duration"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    current_season: Mapped[str] = mapped_column(String(16), server_default="summer")
    season_started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    season_duration_minutes: Mapped[int] = mapped_column(
        Integer, server_default="10080"
    )
    weather: Mapped[str] = mapped_column(String(16), server_default="clear")
    day_cycle_anchor_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    day_night_cycle_minutes: Mapped[int] = mapped_column(Integer, server_default="40")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=utcnow
    )
