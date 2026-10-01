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
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(ProfileService(db).get(pid))


@router.put("")
def put_profile(
    payload: ProfileUpdate,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).update(pid, payload))


@router.post("/save")
def post_save(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(ProfileService(db).heartbeat(pid))


@router.post("/heartbeat")
def post_heartbeat(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(ProfileService(db).heartbeat(pid))


@router.post("/tutorial")
def post_tutorial(
    payload: TutorialRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).tutorial(pid, payload))


@router.post("/hints/{feature}")
def post_hints_feature(
    feature: Literal["movement", "farming", "fishing", "shop", "pets", "social"],
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).hint(pid, feature))


@router.post("/feedback")
def post_feedback(
    payload: FeedbackRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).feedback(pid, payload.message))


@router.post("/delete-account")
def post_delete_account(
    payload: DeleteAccountRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(ProfileService(db).delete_account(pid, payload))
