from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from app.models.world import World


def get_world_by_owner(db: Session, owner_id: int) -> World | None:
    """Return the World owned by the given player, or None if not found."""
    return db.execute(select(World).where(World.owner_id == owner_id)).scalar_one_or_none()


def create_world(db: Session, owner_id: int, name: str = "My World") -> World:
    """Create and persist a new World for the given player."""
    world = World(owner_id=owner_id, name=name, tiles={})
    db.add(world)
    db.commit()
    db.refresh(world)
    return world


def update_tiles(db: Session, world_id: int, tiles: dict) -> World:
    """Replace the entire tiles dictionary for the given World."""
    world = db.get(World, world_id)
    if world is None:
        raise ValueError(f"World with id {world_id} not found")
    world.tiles = tiles
    db.commit()
    db.refresh(world)
    return world


def update_single_tile(db: Session, world_id: int, x: int, y: int, tile_type: str) -> World:
    """Set a single tile at coordinates (x, y) to the given tile_type."""
    world = db.get(World, world_id)
    if world is None:
        raise ValueError(f"World with id {world_id} not found")
    key = f"{x},{y}"
    world.tiles[key] = tile_type
    flag_modified(world, "tiles")
    db.commit()
    db.refresh(world)
    return world
