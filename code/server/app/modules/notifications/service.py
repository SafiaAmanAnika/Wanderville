from sqlalchemy import func, select
from app.core.exceptions import NotFound
from app.core.responses import public
from app.db.session import transaction
from app.modules.notifications.models import Notification
from app.db.repository import Repository
from app.modules.players.repository import PlayerRepository


class NotificationsService:
    def __init__(self, db):
        self.db, self.repo = db, Repository(db)

    def emit(self, player_id, kind, message, target=None, event_key=None):
        if event_key and self.db.scalar(
            select(Notification.id).where(
                Notification.player_id == player_id, Notification.event_key == event_key
            )
        ):
            return
        self.repo.add(
            Notification,
            player_id=player_id,
            kind=kind,
            message=message,
            target=target,
            event_key=event_key,
        )

    def list(self, player_id, before=None, limit=50):
        conditions = [
            Notification.player_id == player_id,
            Notification.dismissed.is_(False),
        ]
        rows, next_cursor = self.repo.keyset_page(
            Notification,
            *conditions,
            before=before,
            limit=limit,
            order=Notification.id.desc(),
        )
        unread = self.db.scalar(
            select(func.count())
            .select_from(Notification)
            .where(
                Notification.player_id == player_id,
                Notification.dismissed.is_(False),
                Notification.is_read.is_(False),
            )
        )
        return {
            "items": [public(r) for r in rows],
            "unread_count": unread,
            "next_cursor": next_cursor,
        }

    def update(self, player_id, notification_id, dismiss=False):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.get(Notification, notification_id)
            if row.player_id != player_id:
                raise NotFound()
            row.is_read = True
            row.dismissed = dismiss
        return public(row)
