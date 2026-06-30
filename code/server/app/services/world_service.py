from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.world import World, WorldState


def create_world(db: Session, player_id: int) -> World:
    world = World(
        owner_id=player_id,
        name="My World",
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