from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.market.service import MarketService

from app.modules.market.schemas import (
    OpenShopRequest,
    ListingRequest,
    UnstockRequest,
    BuyRequest,
)

router = APIRouter(prefix="/market", tags=["market"])


@router.get("")
def get_my_shop(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(MarketService(db).mine(player_id))


@router.post("")
def post_open_shop(
    payload: OpenShopRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(MarketService(db).open(player_id, payload))

@router.get("/friends")
def get_friends_shops(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(MarketService(db).friends_shops(player_id))


@router.get("/{shop_id}/listings")
def get_listings(
    shop_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(MarketService(db).listings(shop_id))


@router.get("/{shop_id}/sales")
def get_sales(
    shop_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(MarketService(db).sales(player_id, shop_id))


@router.post("/listings")
def post_listing(
    payload: ListingRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(MarketService(db).stock(player_id, payload))


@router.post("/listings/remove")
def post_listing_remove(
    payload: UnstockRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(MarketService(db).unstock(player_id, payload))


@router.post("/buy")
def post_buy(
    payload: BuyRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(MarketService(db).buy(player_id, payload))