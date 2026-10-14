from typing import Literal
from fastapi import APIRouter, Depends, Path
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.shop.service import ShopService
from app.modules.shop.schemas import PurchaseRequest, SaleRequest

router = APIRouter(prefix="/shop", tags=["shop"])


@router.get("")
def get_shop(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(ShopService(db).catalog(player_id))


@router.post("/buy")
def post_buy(
    payload: PurchaseRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ShopService(db).buy(player_id, payload))


@router.post("/sell")
def post_sell(
    payload: SaleRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ShopService(db).sell(player_id, payload))


@router.get("/transactions/{request_id}")
def transaction_status(
    request_id: str = Path(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$"),
    action: Literal["buy", "sell"] = "buy",
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db),
):
    return success(ShopService(db).transaction_status(player_id, request_id, action))


@router.post("/starter/claim")
def claim_starter(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(ShopService(db).claim_starter(player_id))


@router.get("/collection")
def get_collection(
    fish_only: bool = False,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ShopService(db).collection(player_id, fish_only))
