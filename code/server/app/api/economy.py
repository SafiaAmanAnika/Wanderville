from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps.auth import get_current_player_id
from app.schemas.economy import EconomyResponse, TransactionRequest, XPResponse, XPGainRequest
from app.schemas.responses import Envelope
from app.services import economy_service

router = APIRouter(prefix="/economy", tags=["economy"])


@router.get("/", response_model=Envelope[EconomyResponse])
def get_economy(
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    economy = economy_service.get_or_create_economy(db, player_id)
    data = EconomyResponse.model_validate(economy)
    return {
        "success": True,
        "data": data.model_dump(),
        "message": "Economy retrieved",
    }


@router.post("/earn", response_model=Envelope[EconomyResponse])
def earn_taka(
    req: TransactionRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    try:
        economy = economy_service.add_taka(db, player_id, req.amount, req.description)
        data = EconomyResponse.model_validate(economy)
        return {
            "success": True,
            "data": data.model_dump(),
            "message": f"Earned {req.amount} taka",
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/spend", response_model=Envelope[EconomyResponse])
def spend_taka(
    req: TransactionRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    try:
        economy = economy_service.spend_taka(db, player_id, req.amount, req.description)
        data = EconomyResponse.model_validate(economy)
        return {
            "success": True,
            "data": data.model_dump(),
            "message": f"Spent {req.amount} taka",
        }
    except economy_service.InsufficientFunds as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/xp", response_model=Envelope[XPResponse])
def get_xp(
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    xp = economy_service.get_or_create_xp(db, player_id)
    data = XPResponse.model_validate(xp)
    return {
        "success": True,
        "data": data.model_dump(),
        "message": "XP retrieved",
    }


@router.post("/xp/gain", response_model=Envelope[XPResponse])
def gain_xp(
    req: XPGainRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    try:
        xp = economy_service.add_xp(db, player_id, req.xp_amount)
        data = XPResponse.model_validate(xp)
        return {
            "success": True,
            "data": data.model_dump(),
            "message": f"Gained {req.xp_amount} XP",
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))