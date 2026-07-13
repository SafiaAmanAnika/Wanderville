from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.world import World, WorldState


def create_world(db: Session, player_id: int, name: str = "My World") -> World:
    world = World(
        owner_id=player_id,
        name=name,
        tiles={},
    )
    db.add(world)
    db.commit()
    db.refresh(world)
    return world


def get_or_create_world_state(db: Session) -> WorldState:
    state = db.query(WorldState).first()
    if not state:
        state = WorldState(
            current_season="summer",
            season_start_time=datetime.now(timezone.utc),
            current_time_of_day=0.0,
        )
        db.add(state)
        db.commit()
        db.refresh(state)
    return state


def get_player_world(db: Session, player_id: int) -> World | None:
    return db.query(World).filter(World.owner_id == player_id).first()


def get_world_by_owner(db: Session, player_id: int) -> World | None:
    return get_player_world(db, player_id)


def get_or_create_player_world(db: Session, player_id: int) -> World:
    world = get_player_world(db, player_id)
    if not world:
        world = create_world(db, player_id)
    return world


def _get_world_or_raise(db: Session, world_id: int) -> World:
    world = db.get(World, world_id)
    if world is None:
        raise ValueError("World not found")
    return world


def update_tiles(db: Session, world_id: int, tiles: dict) -> World:
    world = _get_world_or_raise(db, world_id)
    world.tiles = dict(tiles)
    db.commit()
    db.refresh(world)
    return world


def update_single_tile(db: Session, world_id: int, x: int, y: int, tile_type: str) -> World:
    world = _get_world_or_raise(db, world_id)
    tiles = dict(world.tiles or {})
    tiles[f"{x},{y}"] = tile_type
    world.tiles = tiles
    db.commit()
    db.refresh(world)
    return world


def get_world_state(db: Session) -> WorldState:
    return get_or_create_world_state(db)


def advance_season(db: Session) -> WorldState:
    state = get_or_create_world_state(db)
    seasons = ["summer", "autumn", "winter", "spring"]
    current_idx = seasons.index(state.current_season)
    state.current_season = seasons[(current_idx + 1) % 4]
    state.season_start_time = datetime.now(timezone.utc)
    db.commit()
    db.refresh(state)
    return state