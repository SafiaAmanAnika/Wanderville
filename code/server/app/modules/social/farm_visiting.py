"""Invitation lifecycle and visitor-slot admission.

Two invariants this module exists to hold:

1. **Accepting an invitation trusts nothing.** Every precondition the server
   checked when the invitation was created is re-derived from current state at
   accept time: the invitation must still exist, still belong to this guest,
   still be PENDING, still be inside its expiry, the host and world must still
   exist, the host must still own that world, the guest must not already be
   visiting somewhere, and the farm must still have a free slot.

2. **Slot admission is transactional, not a read-then-write.** Counting free
   slots and inserting the visit session happen inside one transaction that
   holds ``SELECT ... FOR UPDATE`` on the host's world row, so two guests racing
   for the fifth slot are serialized by the database. Both the per-world lock and
   the ordered player locks (a single global order, so the host admitting a
   guest and that guest leaving cannot deadlock) are taken before the count is
   read. The unique ``active_visitor_key`` index is the backstop: even if the
   lock were unavailable, the second insert would fail rather than over-fill.
"""

from datetime import timedelta

from sqlalchemy import String, cast, literal, select
from sqlalchemy.orm import Session

from app.core.clock import as_utc, utcnow
from app.core.exceptions import AppError, NotFound
from app.core.gameplay import public
from app.db.session import transaction
from app.modules.players.repository import PlayerRepository
from app.modules.social.models import FarmInvitation, FarmVisitSession
from app.modules.world.access import (
    capacity,
    farm_full_error,
    owned_world,
)
from app.modules.world.models import PlayerWorld

INVITE_TTL = timedelta(minutes=10)
# How long a visit session may go without a heartbeat before the sweep reclaims
# the slot. Must comfortably exceed the client socket poll interval.
VISIT_HEARTBEAT_TIMEOUT = timedelta(seconds=90)
# Mirrors realtime.service.PRESENCE_TTL_SECONDS. Declared here rather than
# imported so the sweep module does not depend on the realtime service, which
# imports this one.
PRESENCE_TTL_SECONDS = 60

OPEN_STATUSES = ("PENDING", "ACCEPTED")
RESOLVED = ("DECLINED", "EXPIRED", "CANCELLED")


def _active_key(host_id, guest_id, world_id):
    return f"{host_id}:{guest_id}:{world_id}"


def _lock(db: Session, *player_ids, world_id=None):
    """Take advisory locks in one global order.

    Every player row by ascending id first, then the world row. Admission,
    leave and kick all use this single order, so a host admitting a guest and
    that same guest leaving cannot deadlock against one another.
    """
    PlayerRepository(db).lock(
        *sorted({pid for pid in player_ids if pid is not None})
    )
    if world_id is not None:
        db.scalar(
            select(PlayerWorld)
            .where(PlayerWorld.id == world_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )


class FarmVisitService:
    def __init__(self, db):
        self.db = db

    # ---------------------------------------------------------------- reads

    def invitation_public(self, row):
        data = public(row)
        host = self.db.get(PlayerWorld, row.world_id)
        data["world_name"] = host.name if host else None
        # Both ends of the offer are named so a guest can recognise who is
        # asking and a host can see who they are waiting on.
        names = self._usernames([row.host_player_id, row.invited_player_id])
        data["host_username"] = names.get(row.host_player_id, "Player")
        data["guest_username"] = names.get(row.invited_player_id, "Player")
        return data

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
        from app.modules.players.models import Player

        return {
            p.id: p.username
            for p in self.db.scalars(
                select(Player).where(Player.id.in_(set(ids)))
            )
        }

    # ---------------------------------------------------------- invitations

    def invite(self, host_id, guest_id):
        """Host invites one guest. Idempotent on an unexpired open offer."""
        if host_id == guest_id:
            raise AppError("SELF_INTERACTION", "You cannot invite yourself")
        from app.modules.social.service import SocialService

        now = utcnow()
        with transaction(self.db):
            SocialService(self.db).allowed(host_id, guest_id)
            world = owned_world(self.db, host_id)
            _lock(self.db, host_id, guest_id, world_id=world.id)

            existing = self.db.scalar(
                select(FarmInvitation).where(
                    FarmInvitation.host_player_id == host_id,
                    FarmInvitation.invited_player_id == guest_id,
                    FarmInvitation.world_id == world.id,
                    FarmInvitation.status == "PENDING",
                )
            )
            if existing is not None:
                if as_utc(existing.expires_at) > now:
                    # An unexpired offer already exists: return it rather than
                    # creating a second pending row for the same triple.
                    return self.invitation_public(existing)
                existing.status = "EXPIRED"
                existing.active_key = None
                existing.responded_at = now

            row = FarmInvitation(
                host_player_id=host_id,
                invited_player_id=guest_id,
                world_id=world.id,
                status="PENDING",
                active_key=_active_key(host_id, guest_id, world.id),
                expires_at=now + INVITE_TTL,
            )
            self.db.add(row)
            self.db.flush()
            from app.modules.notifications.service import NotificationsService

            NotificationsService(self.db).emit(
                guest_id,
                "farm_invitation",
                f"{self._usernames([host_id]).get(host_id, 'A player')} invited you to visit their farm",
                f"/farm/invitations/{row.id}",
            )
            result = self.invitation_public(row)
        return result

    def cancel(self, host_id, invitation_id):
        """Host withdraws an offer. Resolved offers report as already handled."""
        with transaction(self.db):
            row = self.db.get(FarmInvitation, invitation_id)
            if row is None or row.host_player_id != host_id:
                raise NotFound("Invitation not found")
            _lock(self.db, host_id, row.invited_player_id, world_id=row.world_id)
            row = self.db.get(FarmInvitation, invitation_id)
            if row.status != "PENDING":
                raise AppError(
                    "INVITE_RESOLVED",
                    "This invitation is no longer pending",
                    409,
                )
            self._resolve(row, "CANCELLED")
            result = self.invitation_public(row)
        return result

    def decline(self, guest_id, invitation_id):
        with transaction(self.db):
            row = self.db.get(FarmInvitation, invitation_id)
            if row is None or row.invited_player_id != guest_id:
                raise NotFound("Invitation not found")
            _lock(self.db, guest_id, row.host_player_id, world_id=row.world_id)
            row = self.db.get(FarmInvitation, invitation_id)
            if row.status != "PENDING":
                raise AppError(
                    "INVITE_RESOLVED",
                    "This invitation is no longer pending",
                    409,
                )
            self._resolve(row, "DECLINED")
            result = self.invitation_public(row)
        return result

    @staticmethod
    def _resolve(row, status):
        row.status = status
        row.active_key = None
        row.responded_at = utcnow()

    # --------------------------------------------------------------- accept

    def accept(self, guest_id, invitation_id):
        """Guest accepts: revalidate everything, then reserve a slot atomically.

        A rejected accept deliberately leaves the invitation PENDING. Marking it
        resolved before raising would roll back with the exception and either
        write nothing or, worse, consume an invitation because the farm happened
        to be full at that instant. Staying PENDING lets the guest retry once a
        slot frees up, and the expiry sweep still retires a genuinely stale
        offer.
        """
        from app.modules.social.service import SocialService

        with transaction(self.db):
            row = self.db.get(FarmInvitation, invitation_id)
            if row is None:
                raise NotFound("Invitation not found")
            # Identity check before anything else: a guest may only answer their
            # own offer, and must not be able to learn another pair's invite id.
            if row.invited_player_id != guest_id:
                raise NotFound("Invitation not found")

            host_id, world_id = row.host_player_id, row.world_id
            _lock(self.db, guest_id, host_id, world_id=world_id)
            row = self.db.get(FarmInvitation, invitation_id)

            now = utcnow()
            if row.status != "PENDING":
                raise AppError(
                    "INVITE_RESOLVED",
                    "This invitation is no longer pending",
                    409,
                )
            if as_utc(row.expires_at) <= now:
                raise AppError("INVITE_EXPIRED", "This invitation has expired", 409)

            host_world = self.db.get(PlayerWorld, world_id)
            if host_world is None or host_world.owner_id != host_id:
                # The host deleted their world, or ownership moved. The offer is
                # void rather than silently re-pointed at a different world.
                raise NotFound("The farm is no longer available")

            SocialService(self.db).allowed(guest_id, host_id)

            existing = self.db.scalar(
                select(FarmVisitSession).where(
                    FarmVisitSession.visitor_player_id == guest_id,
                    FarmVisitSession.status == "ACTIVE",
                )
            )
            if existing is not None:
                raise AppError(
                    "ALREADY_VISITING",
                    "Leave your current farm before visiting another",
                    409,
                )

            # Capacity is read under the world lock held above, so a concurrent
            # accept for the same farm cannot also observe a free slot.
            free, limit = capacity(self.db, world_id)
            if free <= 0:
                raise farm_full_error()

            session = FarmVisitSession(
                world_id=world_id,
                host_player_id=host_id,
                visitor_player_id=guest_id,
                status="ACTIVE",
                active_visitor_key=guest_id,
                started_at=now,
                last_seen_at=now,
            )
            self.db.add(session)
            self._resolve(row, "ACCEPTED")
            self.db.flush()

            from app.modules.notifications.service import NotificationsService

            NotificationsService(self.db).emit(
                host_id,
                "farm_visitor_joined",
                f"{self._usernames([guest_id]).get(guest_id, 'A player')} is visiting your farm",
                "/farm/visitors",
            )
            result = {
                "visit_session_id": session.id,
                "invitation_id": row.id,
                "session_mode": "VISITOR",
                "host_player_id": host_id,
                "world_id": world_id,
                "visitor_player_id": guest_id,
                "spawn_x": host_world.farm_entrance_x,
                "spawn_y": host_world.farm_entrance_y,
                "visitor_limit": limit,
                "visitor_count": limit - free + 1,
                "read_only": True,
            }
        return result

    # ----------------------------------------------------------------- exit

    def leave(self, guest_id, reason="LEFT"):
        """Close the visitor's session and free the slot."""
        with transaction(self.db):
            result = self.leave_locked(guest_id, reason)
        return result

    def leave_locked(self, guest_id, reason="LEFT"):
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
        _lock(
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
            _lock(
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
            evicted = self.evict_for_world_locked(host_id, reason)
        return evicted

    def evict_for_world_locked(self, host_id, reason="DISCONNECTED"):
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
        _lock(
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
            return self.heartbeat_locked(guest_id)

    def heartbeat_locked(self, guest_id):
        """``heartbeat`` for callers that already own the transaction."""
        session = self.db.scalar(
            select(FarmVisitSession).where(
                FarmVisitSession.visitor_player_id == guest_id,
                FarmVisitSession.status == "ACTIVE",
            )
        )
        if session is None:
            return None
        session.last_seen_at = utcnow()
        self.db.flush()
        return session.id

    def close_all_for_disconnect(self, player_id, reason="DISCONNECTED"):
        """Release every visit slot tied to one connection dropping.

        Owns its transaction. Prefer ``close_all_for_disconnect_locked`` when the
        caller needs the same commit to carry its own writes.
        """
        with transaction(self.db):
            return self.close_all_for_disconnect_locked(player_id, reason)

    def close_all_for_disconnect_locked(self, player_id, reason="DISCONNECTED"):
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
        world = self.db.query(PlayerWorld).filter(
            PlayerWorld.owner_id == player_id
        ).one_or_none()
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
        from app.modules.realtime.models import Presence

        cutoff = (now or utcnow()) - timedelta(seconds=PRESENCE_TTL_SECONDS)
        expected_room = literal("world:") + cast(FarmVisitSession.world_id, String)
        orphans = list(
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
        reclaimed = []
        for session in orphans:
            with transaction(self.db):
                locked = self.db.scalar(
                    select(FarmVisitSession)
                    .where(FarmVisitSession.id == session.id)
                    .with_for_update()
                    .execution_options(populate_existing=True)
                )
                if locked is None or locked.status != "ACTIVE":
                    continue
                locked.status = "DISCONNECTED"
                locked.active_visitor_key = None
                locked.ended_at = utcnow()
                reclaimed.append(
                    {
                        "visit_session_id": locked.id,
                        "visitor_player_id": locked.visitor_player_id,
                        "host_player_id": locked.host_player_id,
                        "world_id": locked.world_id,
                    }
                )
        return reclaimed

    def sweep_stale(self, now=None, limit=500):
        """Reclaim slots from sessions whose owner vanished without a clean exit.

        The socket close path normally releases the slot immediately; this is the
        safety net for a crash, a killed process, or a dropped connection that
        never produced a close frame.
        """
        cutoff = (now or utcnow()) - VISIT_HEARTBEAT_TIMEOUT
        stale = list(
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
        reclaimed = []
        for session in stale:
            with transaction(self.db):
                locked = self.db.scalar(
                    select(FarmVisitSession)
                    .where(FarmVisitSession.id == session.id)
                    .with_for_update()
                    .execution_options(populate_existing=True)
                )
                if locked is None or locked.status != "ACTIVE":
                    continue
                locked.status = "DISCONNECTED"
                locked.active_visitor_key = None
                locked.ended_at = utcnow()
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
    "INVITE_TTL",
    "VISIT_HEARTBEAT_TIMEOUT",
]