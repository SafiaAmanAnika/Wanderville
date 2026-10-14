from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.fishing.service import FishingService
from app.modules.fishing.schemas import CastRequest, CatchRequest

router = APIRouter(prefix="/fishing", tags=["fishing"])


@router.post("/cast")
def post_cast(
    payload: CastRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FishingService(db).cast(player_id, payload))


@router.post("/catch")
def post_catch(
    payload: CatchRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FishingService(db).catch(player_id, payload.cast_id))


@router.post("/drops/{drop_id}/claim")
def post_drops_drop_id_claim(
    drop_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FishingService(db).claim(player_id, drop_id))


@router.get("/spots")
def get_spots(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(FishingService(db).spots())


@router.get("/drops")
def get_drops(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(FishingService(db).drops(player_id))
