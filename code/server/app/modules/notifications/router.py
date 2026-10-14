from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.notifications.service import NotificationsService
from app.modules.notifications.schemas import NotificationUpdate

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("")
def get_notifications(
    before: int | None = Query(None, gt=0),
    limit: int = Query(50, ge=1, le=100),
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(NotificationsService(db).list(player_id, before, limit))


@router.post("/{notification_id}")
def post_notification_id(
    payload: NotificationUpdate,
    notification_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(
        NotificationsService(db).update(player_id, notification_id, payload.dismiss)
    )
