from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.events.service import EventsService

router = APIRouter(prefix="/events", tags=["events"])


@router.get("")
def get_events(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(EventsService(db).list())


@router.post("/{code}/claim")
def post_code_claim(
    code: str, pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(EventsService(db).claim(pid, code))
