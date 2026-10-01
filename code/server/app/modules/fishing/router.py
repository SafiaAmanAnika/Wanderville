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
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FishingService(db).cast(pid, payload))


@router.post("/catch")
def post_catch(
    payload: CatchRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FishingService(db).catch(pid, payload.cast_id))


@router.post("/drops/{drop_id}/claim")
def post_drops_drop_id_claim(
    drop_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(FishingService(db).claim(pid, drop_id))


@router.get("/spots")
def get_spots(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(FishingService(db).spots())


@router.get("/drops")
def get_drops(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(FishingService(db).drops(pid))
