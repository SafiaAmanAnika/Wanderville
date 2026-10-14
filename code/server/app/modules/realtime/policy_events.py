"""Invalidate permissions only after durable policy changes commit."""

from sqlalchemy import event, inspect
from sqlalchemy.orm import Session
from app.modules.realtime.runtime import runtime
from app.modules.realtime.models import Presence
from app.modules.social.models import Friendship, PlayerBlock, FarmVisitSession
from app.modules.social.community_models import SocialPreferences
from app.modules.players.models import Player


@event.listens_for(Session, "before_flush")
def collect_changes(db, _context, _instances):
    invalidate = db.info.setdefault("voice_invalidate", set())
    leave = db.info.setdefault("voice_leave", set())
    for row in set(db.new) | set(db.dirty) | set(db.deleted):
        if isinstance(row, Friendship):
            invalidate.update((row.low_id, row.high_id))
        elif isinstance(row, PlayerBlock):
            invalidate.update((row.player_id, row.blocked_id))
        elif isinstance(row, SocialPreferences):
            invalidate.add(row.player_id)
            if row.voice_privacy == "off":
                leave.add(row.player_id)
        elif (
            isinstance(row, FarmVisitSession)
            and inspect(row).attrs.status.history.has_changes()
        ):
            invalidate.update((row.host_player_id, row.visitor_player_id))
            leave.add(row.visitor_player_id)
        elif (
            isinstance(row, Presence)
            and inspect(row).attrs.room_epoch.history.has_changes()
        ):
            invalidate.add(row.player_id)
            leave.add(row.player_id)
        elif (
            isinstance(row, Player)
            and inspect(row).attrs.is_active.history.has_changes()
        ):
            invalidate.add(row.id)
            if not row.is_active:
                leave.add(row.id)


@event.listens_for(Session, "after_commit")
def committed(db):
    players = db.info.pop("voice_invalidate", set())
    leave = db.info.pop("voice_leave", set())
    if players:
        runtime.invalidate(players)
    if leave:
        runtime.invalidate(leave, leave=True)


@event.listens_for(Session, "after_rollback")
def rolled_back(db):
    db.info.pop("voice_invalidate", None)
    db.info.pop("voice_leave", None)
