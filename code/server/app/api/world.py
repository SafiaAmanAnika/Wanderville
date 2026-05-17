from __future__ import annotations

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps.auth import check_owner, get_current_player_id
from app.schemas.responses import TileUpdateResponse, WorldResponse
from app.schemas.world import TileUpdate, TilesBulkUpdate, WorldPublic
from app.services import world_service


router = APIRouter(prefix="/world", tags=["world"])


@router.get("/me", response_model=WorldResponse)
def get_my_world(
    db: Session = Depends(get_db),
    player_id: int = Depends(get_current_player_id),
):
    """Return the current player's world, creating one if it does not exist. Requires valid JWT token."""
    world = world_service.get_world_by_owner(db, player_id)
    if world is None:
        world = world_service.create_world(db, player_id)

    return {
        "success": True,
        "data": WorldPublic.model_validate(world).model_dump(),
        "message": "OK",
    }


@router.put("/tiles", response_model=WorldResponse)
def update_world_tiles(
    payload: TilesBulkUpdate,
    db: Session = Depends(get_db),
    player_id: int = Depends(get_current_player_id),
):
    """Replace the entire tiles dictionary for the current player's world. Requires valid JWT token."""
    world = world_service.get_world_by_owner(db, player_id)
    if world is None:
        return JSONResponse(
            status_code=404,
            content={"success": False, "error": "NOT_FOUND", "message": "World not found"},
        )

    check_owner(world.owner_id, player_id)

    tiles = payload.tiles

    world = world_service.update_tiles(db, world.id, tiles)

    return {
        "success": True,
        "data": WorldPublic.model_validate(world).model_dump(),
        "message": "Tiles updated",
    }


@router.put("/tile", response_model=TileUpdateResponse)
def update_single_tile(
    payload: TileUpdate,
    db: Session = Depends(get_db),
    player_id: int = Depends(get_current_player_id),
):
    """Set a single tile at (x, y) for the current player's world. Requires valid JWT token."""
    world = world_service.get_world_by_owner(db, player_id)
    if world is None:
        return JSONResponse(
            status_code=404,
            content={"success": False, "error": "NOT_FOUND", "message": "World not found"},
        )

    check_owner(world.owner_id, player_id)

    world = world_service.update_single_tile(db, world.id, payload.x, payload.y, payload.tile_type)

    return {
        "success": True,
        "data": WorldPublic.model_validate(world).model_dump(),
        "message": "Tile updated",
    }
