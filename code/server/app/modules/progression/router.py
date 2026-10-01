from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.progression.service import ProgressionService

router = APIRouter(prefix="/progression", tags=["progression"])


@router.get("/goals")
def get_goals(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(ProgressionService(db).goals(pid))


@router.get("/statistics")
def get_statistics(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(ProgressionService(db).stats(pid))
