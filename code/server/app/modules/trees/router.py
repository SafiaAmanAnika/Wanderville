from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.responses import success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.trees.schemas import ChopRequest
from app.modules.trees.service import TreeService

router = APIRouter(prefix="/trees", tags=["trees"])


@router.get("")
def get_forest(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(TreeService(db).forest(player_id))


@router.post("/chop")
def post_chop(
    payload: ChopRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(TreeService(db).chop(player_id, payload.tree_id, payload.avoid))
