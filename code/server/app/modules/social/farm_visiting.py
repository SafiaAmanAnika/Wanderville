"""Farm visit sessions: who is standing in whose farm, and how that ends.

An invitation (see :mod:`app.modules.social.farm_invitations`) is an *offer*; a
visit session is the *occupancy* it produces. This module owns the occupancy:
admission results, the visitors list, every exit path (leave, kick, evict,
heartbeat, disconnect) and the sweeps that reclaim slots nobody released.

Two invariants live here:

1. **A slot is held only while somebody is actually there.** Every exit path --
   an explicit leave, a host kick, a host going offline, a crashed client -- ends
   the session through the same code, so "closing a tab frees slots exactly like
   the button" is true by construction rather than by convention.

2. **Exits are re-entrant-safe.** ``leave_internal`` and friends flush without
   committing so a caller can end several visits in one transaction; the public
   wrappers own the boundary. That split is what lets logout revoke a token and
   release every affected visit in a single commit.
"""

from datetime import timedelta

from sqlalchemy import String, cast, literal, select

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.core.exceptions import AppError, NotFound
from app.core.responses import public
from app.db.session import transaction
from app.modules.notifications.service import NotificationsService
from app.modules.players.models import Player
from app.modules.players.repository import PlayerRepository
from app.modules.realtime.models import Presence
from app.modules.social.farm_invitations import (
    FarmInvitationService,
    invitation_public,
)
from app.modules.social.models import FarmInvitation, FarmVisitSession
from app.modules.social.visit_locking import (
    OPEN_STATUSES,
    RESOLVED,
    VISIT_HEARTBEAT_TIMEOUT,
    lock_rows,
)
from app.modules.world.access import capacity, owned_world
from app.modules.world.models import PlayerWorld

# Mirrors realtime.service.PRESENCE_TTL_SECONDS. Read through settings so the
# sweep and the socket cannot drift apart while this module stays independent of
# the realtime service, which imports this one.
PRESENCE_TTL_SECONDS = settings.presence_ttl_seconds


class FarmVisitService:
    def __init__(self, db):
        self.db = db

    # ---------------------------------------------------------------- reads

    def invitation_public(self, row):
        """Delegate to the invitation module; kept for existing callers."""
        return invitation_public(self.db, row)

    def inbox(self, guest_id, include_resolved=False):
        """Open offers for the guest. Resolved offers are hidden by default so
        the inbox is not a permanent list of declined history."""
        conditions = [FarmInvitation.invited_player_id == guest_id]
        if not include_resolved:
            conditions.append(FarmInvitation.status.in_(OPEN_STATUSES))
        rows = self.db.scalars(
            select(FarmInvitation)
            .where(*conditions)
            .order_by(FarmInvitation.id.desc())
            .limit(200)
        )
        return [self.invitation_public(r) for r in rows]

    def outgoing(self, host_id, include_resolved=False):
        conditions = [FarmInvitation.host_player_id == host_id]
        if not include_resolved:
            conditions.append(FarmInvitation.status.in_(OPEN_STATUSES))
        rows = self.db.scalars(
            select(FarmInvitation)
            .where(*conditions)
            .order_by(FarmInvitation.id.desc())
            .limit(200)
        )
        return [self.invitation_public(r) for r in rows]

    def visitors(self, host_id):
        """Current occupancy of the host's farm. The owner does not count."""
        world = owned_world(self.db, host_id)
        rows = list(
            self.db.scalars(
                select(FarmVisitSession)
                .where(
                    FarmVisitSession.world_id == world.id,
                    FarmVisitSession.status == "ACTIVE",
                )
                .order_by(FarmVisitSession.id)
            )
        )
        names = self._usernames([r.visitor_player_id for r in rows])
        free, limit = capacity(self.db, world.id)
        return {
            "world_id": world.id,
            "visitor_limit": limit,
            "visitor_count": len(rows),
            "free_slots": free,
            "visitors": [
                {
                    "visit_session_id": r.id,
                    "player_id": r.visitor_player_id,
                    "username": names.get(r.visitor_player_id, "Player"),
                    "started_at": as_utc(r.started_at),
                }
                for r in rows
            ],
        }

    def _usernames(self, ids):
        if not ids:
            return {}
        return {
            p.id: p.username
            for p in self.db.scalars(
                select(Player).where(Player.id.in_(set(ids)))
            )
        }

    # ---------------------------------------------------------- invitations
    #
    # The invitation lifecycle lives in FarmInvitationService. These four
    # delegations keep one public entry point for the whole visiting feature, so
    # no caller has to know which of the two modules a given action belongs to.

    def invite(self, host_id, guest_id):
        """Host invites one guest. Idempotent on an unexpired open offer."""
        return FarmInvitationService(self.db).invite(host_id, guest_id)

    def cancel(self, host_id, invitation_id):
        """Host withdraws an offer. Resolved offers report as already handled."""
        return FarmInvitationService(self.db).cancel(host_id, invitation_id)

    def decline(self, guest_id, invitation_id):
        """Guest turns the offer down."""
        return FarmInvitationService(self.db).decline(guest_id, invitation_id)

    def accept(self, guest_id, invitation_id):
        """Guest accepts: revalidate everything, then reserve a slot atomically."""
        return FarmInvitationService(self.db).accept(guest_id, invitation_id)

    # ----------------------------------------------------------------- exit

    def leave(self, guest_id, reason="LEFT"):
        """Close the visitor's session and free the slot."""
        with transaction(self.db):
            result = self.leave_internal(guest_id, reason)
        return result

    def leave_internal(self, guest_id, reason="LEFT"):
        """``leave`` for callers that already own the transaction boundary.

        Returns ``None`` when the guest holds no active session, so a duplicated
        Leave Farm press (or a logout racing a disconnect) is idempotent rather
        than an error. Locks are taken in the same single global order as every
        other exit path, so callers must not have locked a subset already.
        """
        session = self.db.scalar(
            select(FarmVisitSession).where(
                FarmVisitSession.visitor_player_id == guest_id,
                FarmVisitSession.status == "ACTIVE",
            )
        )
        if session is None:
            return None
        lock_rows(
            self.db,
            guest_id,
            session.host_player_id,
            world_id=session.world_id,
        )
        session = self.db.scalar(
            select(FarmVisitSession)
            .where(
                FarmVisitSession.visitor_player_id == guest_id,
                FarmVisitSession.status == "ACTIVE",
            )
            .execution_options(populate_existing=True)
        )
        if session is None:
            return None
        world_id, host_id = session.world_id, session.host_player_id
        session.status = reason
        session.active_visitor_key = None
        session.ended_at = utcnow()
        self.db.flush()
        own = owned_world(self.db, guest_id)
        return {
            "reason": reason,
            "left_world_id": world_id,
            "host_player_id": host_id,
            "current_world_id": own.id,
            "owned_world_id": own.id,
            "session_mode": "OWNER",
        }

    def kick(self, host_id, visit_session_id):
        """Owner removes a visitor."""
        with transaction(self.db):
            session = self.db.get(FarmVisitSession, visit_session_id)
            if session is None or session.host_player_id != host_id:
                raise NotFound("Visit session not found")
            lock_rows(
                self.db,
                host_id,
                session.visitor_player_id,
                world_id=session.world_id,
            )
            session = self.db.get(FarmVisitSession, visit_session_id)
            if session.status != "ACTIVE":
                raise AppError(
                    "VISIT_NOT_ACTIVE", "That visitor has already left", 409
                )
            session.status = "KICKED"
            session.active_visitor_key = None
            session.ended_at = utcnow()
            self.db.flush()
            result = {
                "visit_session_id": session.id,
                "visitor_player_id": session.visitor_player_id,
                "reason": "KICKED",
            }
        return result

    def evict_for_world(self, host_id, reason="DISCONNECTED"):
        """Close every active visit to one host's farm (host went offline)."""
        with transaction(self.db):
            evicted = self.evict_for_world_internal(host_id, reason)
        return evicted

    def evict_for_world_internal(self, host_id, reason="DISCONNECTED"):
        """``evict_for_world`` for callers that already own the transaction.

        Returns the ids of the visitors whose slot was reclaimed, so the caller
        can tell them why they were removed.
        """
        world = owned_world(self.db, host_id)
        active = list(
            self.db.scalars(
                select(FarmVisitSession).where(
                    FarmVisitSession.world_id == world.id,
                    FarmVisitSession.status == "ACTIVE",
                )
            )
        )
        if not active:
            return []
        lock_rows(
            self.db,
            *([host_id] + [r.visitor_player_id for r in active]),
            world_id=world.id,
        )
        evicted = []
        for session in self.db.scalars(
            select(FarmVisitSession).where(
                FarmVisitSession.world_id == world.id,
                FarmVisitSession.status == "ACTIVE",
            )
        ):
            session.status = reason
            session.active_visitor_key = None
            session.ended_at = utcnow()
            evicted.append(session.visitor_player_id)
        self.db.flush()
        return evicted

    def heartbeat(self, guest_id):
        """Refresh a visitor's liveness stamp. Owner sessions need no stamp.

        Owns its transaction because the socket loop calls it from the read-only
        snapshot path, where the session is rolled back at the end of the frame
        and a flush-only write would never reach the database.
        """
        with transaction(self.db):
            return self.heartbeat_internal(guest_id)

    def heartbeat_internal(self, guest_id):
        """``heartbeat`` for callers that already own the transaction."""
        session = self.db.scalar(
            select(FarmVisitSession).where(
                FarmVisitSession.visitor_player_id == guest_id,
                FarmVisitSession.status == "ACTIVE",
            )
        )
        if session is None:
            return None
        # A live socket checks often; persisting each check wastes database
        # traffic. Stay well inside the presence TTL used by stale-session sweeps.
        if session.last_seen_at and (utcnow() - as_utc(session.last_seen_at)).total_seconds() < min(15, settings.presence_ttl_seconds / 3):
            return session.id
        session.last_seen_at = utcnow()
        self.db.flush()
        return session.id

    def close_all_for_disconnect(self, player_id, reason="DISCONNECTED"):
        """Release every visit slot tied to one connection dropping.

        Owns its transaction. Prefer ``close_all_for_disconnect_internal`` when the
        caller needs the same commit to carry its own writes.
        """
        with transaction(self.db):
            return self.close_all_for_disconnect_internal(player_id, reason)

    def close_all_for_disconnect_internal(self, player_id, reason="DISCONNECTED"):
        """``close_all_for_disconnect`` for callers that already own the boundary.

        A disconnect cuts both directions at once, so both are handled together:
        this player as a *visitor* (their own slot) and this player's farm as
        the *host* (everyone standing in it). Doing it in one pass is also what
        makes the locking safe: the union of affected players is locked ascending
        by id and then the affected worlds ascending, so this cannot deadlock
        against a concurrent accept, kick or the other player's own disconnect.

        Returns the visitor ids that were removed from this player's farm, so the
        caller knows who to tell.
        """
        world = self.db.scalar(
            select(PlayerWorld).where(
                PlayerWorld.owner_id == player_id
            ).execution_options(populate_existing=True)
        )
        affected = list(
            self.db.scalars(
                select(FarmVisitSession).where(
                    FarmVisitSession.status == "ACTIVE",
                    (FarmVisitSession.visitor_player_id == player_id)
                    | (FarmVisitSession.host_player_id == player_id),
                )
            )
        )
        player_ids = {player_id}
        world_ids = set()
        if world is not None:
            world_ids.add(world.id)
        for session in affected:
            player_ids.add(session.host_player_id)
            player_ids.add(session.visitor_player_id)
            world_ids.add(session.world_id)
        PlayerRepository(self.db).lock(*player_ids)
        for world_id in sorted(world_ids):
            self.db.scalar(
                select(PlayerWorld)
                .where(PlayerWorld.id == world_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )
        now = utcnow()
        removed = []
        for session in self.db.scalars(
            select(FarmVisitSession).where(
                FarmVisitSession.status == "ACTIVE",
                (FarmVisitSession.visitor_player_id == player_id)
                | (FarmVisitSession.host_player_id == player_id),
            )
        ):
            session.status = reason
            session.active_visitor_key = None
            session.ended_at = now
            if session.host_player_id == player_id:
                removed.append(session.visitor_player_id)
        self.db.flush()
        return removed

    def sweep_orphaned(self, now=None, limit=500):
        """Reclaim sessions whose host is no longer standing in their farm.

        ``sweep_stale`` only knows about a *visitor* going quiet. A visitor whose
        socket is still healthy keeps heartbeating even after the host's process
        died, so without this pass their slot would be held forever. The host
        presence row is the independent signal: no row, a stale row, or a row in
        a different room all mean the host is not there.
        """
        cutoff = (now or utcnow()) - timedelta(seconds=PRESENCE_TTL_SECONDS)
        expected_room = literal("world:") + cast(FarmVisitSession.world_id, String)
        return self._reclaim(
            self.db.scalars(
                select(FarmVisitSession)
                .outerjoin(Presence, Presence.player_id == FarmVisitSession.host_player_id)
                .where(
                    FarmVisitSession.status == "ACTIVE",
                    (Presence.player_id.is_(None))
                    | (Presence.updated_at < cutoff)
                    | (Presence.room != expected_room),
                )
                .order_by(FarmVisitSession.id)
                .limit(limit)
            )
        )

    def sweep_stale(self, now=None, limit=500):
        """Reclaim slots from sessions whose owner vanished without a clean exit.

        The socket close path normally releases the slot immediately; this is the
        safety net for a crash, a killed process, or a dropped connection that
        never produced a close frame.
        """
        cutoff = (now or utcnow()) - VISIT_HEARTBEAT_TIMEOUT
        return self._reclaim(
            self.db.scalars(
                select(FarmVisitSession)
                .where(
                    FarmVisitSession.status == "ACTIVE",
                    FarmVisitSession.last_seen_at < cutoff,
                )
                .order_by(FarmVisitSession.id)
                .limit(limit)
            )
        )

    def _reclaim(self, candidates):
        """End every candidate session in one transaction.

        Both sweeps differ only in *which* rows they select, so they share this
        loop. It re-reads each row under ``FOR UPDATE`` rather than trusting the
        selection query, because a session can be accepted, kicked or left
        between the moment it was picked and the moment it is ended.

        One transaction for the whole batch rather than one per row: a sweep of
        500 orphans previously meant 500 commits, and a failure part-way through
        reclaimed only some of them while still releasing every slot it had
        already ended.
        """
        reclaimed = []
        with transaction(self.db):
            ended_at = utcnow()
            for candidate in candidates:
                locked = self.db.scalar(
                    select(FarmVisitSession)
                    .where(FarmVisitSession.id == candidate.id)
                    .with_for_update()
                    .execution_options(populate_existing=True)
                )
                if locked is None or locked.status != "ACTIVE":
                    continue
                locked.status = "DISCONNECTED"
                locked.active_visitor_key = None
                locked.ended_at = ended_at
                reclaimed.append(
                    {
                        "visit_session_id": locked.id,
                        "visitor_player_id": locked.visitor_player_id,
                        "host_player_id": locked.host_player_id,
                        "world_id": locked.world_id,
                    }
                )
        return reclaimed


__all__ = [
    "FarmVisitService",
    "PRESENCE_TTL_SECONDS",
    "VISIT_HEARTBEAT_TIMEOUT",
    "invitation_public",
]
