from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.responses import Envelope, success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.economy.schemas import (
    EconomyResponse,
    TransactionRequest,
    TransactionResponse,
    XPGainRequest,
    XPResponse,
)
from app.modules.economy.service import EconomyService

router = APIRouter(prefix="/economy", tags=["economy"])


@router.get("/", response_model=Envelope[EconomyResponse])
def economy(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(EconomyService(db).get(player_id))


@router.post(
    "/earn",
    response_model=Envelope[EconomyResponse],
    description="Development compatibility rewards only.",
)
def earn(
    payload: TransactionRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(
        EconomyService(db).change(player_id, payload, earn=True), "Aura earned"
    )


@router.post("/spend", response_model=Envelope[EconomyResponse])
def spend(
    payload: TransactionRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(
        EconomyService(db).change(player_id, payload, earn=False), "Aura spent"
    )


@router.get("/xp", response_model=Envelope[XPResponse])
def xp(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(EconomyService(db).xp(player_id))


@router.post(
    "/xp/gain",
    response_model=Envelope[XPResponse],
    description="Development compatibility rewards only.",
)
def gain(
    payload: XPGainRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(
        EconomyService(db).gain_compatibility(player_id, payload), "XP gained"
    )


@router.get("/transactions", response_model=Envelope[list[TransactionResponse]])
def history(
    limit: int = Query(20, ge=1, le=100),
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(EconomyService(db).history(player_id, limit))
