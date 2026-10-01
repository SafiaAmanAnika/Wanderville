from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.shop.service import ShopService
from app.modules.shop.schemas import PurchaseRequest
from app.modules.inventory.schemas import ItemRequest

router = APIRouter(prefix="/shop", tags=["shop"])


@router.get("")
def get_shop(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(ShopService(db).catalog(pid))


@router.post("/buy")
def post_buy(
    payload: PurchaseRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ShopService(db).buy(pid, payload))


@router.post("/sell")
def post_sell(
    payload: ItemRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ShopService(db).sell(pid, payload))


@router.get("/collection")
def get_collection(
    fish_only: bool = False,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ShopService(db).collection(pid, fish_only))
