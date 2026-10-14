from fastapi import APIRouter, Depends, Query, Path
from sqlalchemy.orm import Session
from app.core.responses import success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.social.community import CommunityService
from app.modules.social.community_schemas import PreferencesRequest, WishlistRequest

router = APIRouter(prefix="/social", tags=["social"])


@router.get("/preferences")
def preferences(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(CommunityService(db).preferences(pid))


@router.patch("/preferences")
def update_preferences(
    payload: PreferencesRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(CommunityService(db).update_preferences(pid, payload))


@router.get("/wishlist")
def wishlist(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(CommunityService(db).wishlist(pid, pid))


@router.get("/players/{player_id}/wishlist")
def friend_wishlist(
    player_id: int = Path(gt=0),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(CommunityService(db).wishlist(pid, player_id))


@router.put("/wishlist/{item_code}")
def put_wishlist(
    payload: WishlistRequest,
    item_code: str = Path(min_length=1, max_length=32),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(CommunityService(db).put(pid, item_code, payload))


@router.delete("/wishlist/{item_code}")
def remove_wishlist(
    item_code: str = Path(min_length=1, max_length=32),
    expected_version: int = Query(gt=0),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(CommunityService(db).remove(pid, item_code, expected_version))


@router.get("/gifts/requests/{request_id}")
def gift_receipt(
    request_id: str = Path(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$"),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(CommunityService(db).gift_receipt(pid, request_id))


@router.get("/wishlist/{item_code}")
def own_wishlist_item(
    item_code: str = Path(min_length=1, max_length=32),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(CommunityService(db).own_entry(pid, item_code))
