from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.responses import Envelope, success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.state.schemas import StateBundleResponse
from app.modules.state.service import build_bundle

router = APIRouter(prefix="/state", tags=["state"])


@router.get(
    "/bundle",
    response_model=Envelope[StateBundleResponse],
    summary="All gameplay sections in one round trip",
)
def bundle(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    """Replaces the client's six sequential gameplay reads after each action.

    Every section matches its standalone endpoint exactly, so this is additive:
    the individual routes remain available and unchanged.
    """
    return success(build_bundle(db, player_id))