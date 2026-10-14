from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.profile.service import ProfileService
from app.modules.profile.schemas import (
    ProfileUpdate,
    TutorialRequest,
    FeedbackRequest,
    DeleteAccountRequest,
)
from typing import Literal

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("")
def get_profile(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(ProfileService(db).get(player_id))


@router.put("")
def put_profile(
    payload: ProfileUpdate,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).update(player_id, payload))


@router.post("/save")
def post_save(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(ProfileService(db).heartbeat(player_id))


@router.post("/heartbeat")
def post_heartbeat(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(ProfileService(db).heartbeat(player_id))


@router.post("/tutorial")
def post_tutorial(
    payload: TutorialRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).tutorial(player_id, payload))


@router.post("/hints/{feature}")
def post_hints_feature(
    feature: Literal["movement", "farming", "fishing", "shop", "pets", "social"],
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).hint(player_id, feature))


@router.post("/feedback")
def post_feedback(
    payload: FeedbackRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).feedback(player_id, payload.message))


@router.post("/delete-account")
def post_delete_account(
    payload: DeleteAccountRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).delete_account(player_id, payload))
