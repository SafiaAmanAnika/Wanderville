from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.pets.service import PetsService
from app.modules.pets.schemas import PetAction, PetSelection

router = APIRouter(prefix="/pets", tags=["pets"])


@router.get("")
def get_pets(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(PetsService(db).get(player_id))


@router.post("/actions")
def post_actions(
    payload: PetAction,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(PetsService(db).act(player_id, payload))


@router.put("")
def choose_pet(
    payload: PetSelection,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(PetsService(db).choose(player_id, payload))
