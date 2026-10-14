"""Invalidate permissions only after durable policy changes commit.

Listeners are attached by calling :func:`register`, not by importing this
module. Permission revocation must happen on *commit*, never on flush, because a
rolled-back transaction would otherwise have already revoked a live voice
session; and because a policy change that never reaches the database must leave
every session untouched.

Registering explicitly means the wiring is greppable from ``app/main.py`` instead
of being an invisible side effect of an import somewhere in the graph.
"""

from sqlalchemy import event, inspect
from sqlalchemy.orm import Session

from app.modules.players.models import Player
from app.modules.realtime.models import Presence
from app.modules.realtime.runtime import runtime
from app.modules.social.community_models import SocialPreferences
from app.modules.social.models import FarmVisitSession, Friendship, PlayerBlock

_REGISTERED = False


def _collect_changes(db, _context, _instances):
    """Stage which players must lose voice/presence permissions.

    Runs before the flush that will write these rows, so it sees the intended
    final state rather than whatever happens to be in the session.
    """
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


def _committed(db):
    """Revoke permissions for everything that just became durable."""
    players = db.info.pop("voice_invalidate", set())
    leave = db.info.pop("voice_leave", set())
    if players:
        runtime.invalidate(players)
    if leave:
        runtime.invalidate(leave, leave=True)


def _rolled_back(db):
    """Discard staged revocations; a rollback must not revoke anything."""
    db.info.pop("voice_invalidate", None)
    db.info.pop("voice_leave", None)


def register():
    """Attach the listeners once per process."""
    global _REGISTERED
    if _REGISTERED:
        return
    event.listen(Session, "before_flush", _collect_changes)
    event.listen(Session, "after_commit", _committed)
    event.listen(Session, "after_rollback", _rolled_back)
    _REGISTERED = True
