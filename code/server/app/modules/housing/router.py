from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.housing.service import HousingService
from app.modules.housing.schemas import UpgradeRequest, DecorationRequest

router = APIRouter(prefix="/housing", tags=["housing"])


@router.get("")
def get_housing(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(HousingService(db).get(pid))


@router.post("/upgrade")
def post_upgrade(
    payload: UpgradeRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(HousingService(db).upgrade(pid, payload.expected_tier))


@router.post("/decorations")
def post_decorations(
    payload: DecorationRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(HousingService(db).place(pid, payload))


@router.post("/decorations/{decoration_id}/remove")
def post_decorations_decoration_id_remove(
    decoration_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(HousingService(db).remove(pid, decoration_id))
