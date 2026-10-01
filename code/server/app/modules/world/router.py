from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.responses import Envelope, success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.world.schemas import WorldPublic, WorldStateResponse
from app.modules.world.service import WorldService

router = APIRouter(prefix="/world", tags=["world"])


@router.get("/me", response_model=Envelope[WorldPublic])
def mine(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(WorldService(db).get(player_id))


@router.get("/state", response_model=Envelope[WorldStateResponse])
def state(
    _player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(WorldService(db).state())


@router.post("/advance-season", response_model=Envelope[WorldStateResponse])
def advance(
    _player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(WorldService(db).advance_compatibility())


@router.put("/tile", deprecated=True)
@router.put("/tiles", deprecated=True)
def retired(_player_id: int = Depends(get_current_player_id)):
    return WorldService.retired_tiles()
