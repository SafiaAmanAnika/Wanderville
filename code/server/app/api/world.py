from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps.auth import get_current_player_id
from app.schemas.responses import Envelope
from app.schemas.world import WorldPublic, WorldStateResponse, TilesBulkUpdate, TileUpdate
from app.services import world_service

router = APIRouter(prefix="/world", tags=["world"])


@router.get("/me", response_model=Envelope[WorldPublic])
def get_my_world(
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    world = world_service.get_or_create_player_world(db, player_id)
    data = WorldPublic.model_validate(world)
    return {"success": True, "data": data.model_dump(), "message": "World retrieved"}


@router.put("/tiles", response_model=Envelope[WorldPublic])
def update_tiles(
    req: TilesBulkUpdate,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    world = world_service.get_or_create_player_world(db, player_id)
    updated = world_service.update_tiles(db, world.id, req.tiles)
    data = WorldPublic.model_validate(updated)
    return {"success": True, "data": data.model_dump(), "message": "Tiles updated"}


@router.put("/tile", response_model=Envelope[WorldPublic])
def update_single_tile(
    req: TileUpdate,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    world = world_service.get_or_create_player_world(db, player_id)
    updated = world_service.update_single_tile(db, world.id, req.x, req.y, req.tile_type)
    data = WorldPublic.model_validate(updated)
    return {"success": True, "data": data.model_dump(), "message": "Tile updated"}


@router.get("/state", response_model=Envelope[WorldStateResponse])
def get_world_state(
    db: Session = Depends(get_db),
):
    state = world_service.get_world_state(db)
    data = WorldStateResponse.model_validate(state)
    return {
        "success": True,
        "data": data.model_dump(),
        "message": "World state retrieved",
    }


@router.post("/advance-season", response_model=Envelope[WorldStateResponse])
def advance_season(
    db: Session = Depends(get_db),
):
    state = world_service.advance_season(db)
    data = WorldStateResponse.model_validate(state)
    return {
        "success": True,
        "data": data.model_dump(),
        "message": f"Advanced to {state.current_season}",
    }