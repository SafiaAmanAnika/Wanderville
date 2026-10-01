from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.pets.service import PetsService
from app.modules.pets.schemas import PetAction

router = APIRouter(prefix="/pets", tags=["pets"])


@router.get("")
def get_pets(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(PetsService(db).get(pid))


@router.post("/actions")
def post_actions(
    payload: PetAction,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(PetsService(db).act(pid, payload))
