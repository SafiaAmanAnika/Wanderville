"""Farm invitation lifecycle: create, withdraw, decline, accept.

Separated from :mod:`app.modules.social.farm_visiting` because an invitation and
a visit session are different things with different lifetimes and different
failure modes:

* an **invitation** is an offer that may sit PENDING for ten minutes and is
  answered exactly once;
* a **visit session** exists only while somebody is actually standing in the
  farm, and is reclaimed by a sweep when they are not.

The one invariant that spans both -- **accepting trusts nothing** -- lives on
:meth:`FarmInvitationService.accept`, because accept is the only moment where an
untrusted fact becomes a reserved slot.

Every precondition checked when the invitation was created is re-derived from
current state at accept time: the invitation must still exist, still belong to
this guest, still be PENDING, still be inside its expiry, the host and world must
still exist, the host must still own that world, the guest must not already be
visiting somewhere, and the farm must still have a free slot.
"""

from sqlalchemy import select

from app.core.clock import as_utc, utcnow
from app.core.exceptions import AppError, NotFound
from app.core.responses import public
from app.db.session import transaction
from app.modules.notifications.service import NotificationsService
from app.modules.players.models import Player
from app.modules.social.models import FarmInvitation, FarmVisitSession
from app.modules.social.visit_locking import INVITE_TTL, active_key, lock_rows
from app.modules.world.access import capacity, farm_full_error, owned_world
from app.modules.world.models import PlayerWorld


def _usernames(db, ids):
    """Resolve display names, defaulting to a neutral label."""
    ids = set(ids)
    if not ids:
        return {}
    return {
        player.id: player.username
        for player in db.scalars(select(Player).where(Player.id.in_(ids)))
    }


def invitation_public(db, row):
    """Public shape of one invitation.

    Both ends of the offer are named so a guest can recognise who is asking and a
    host can see who they are waiting on, and the host's farm is named so the
    offer is still readable after the world is deleted.
    """
    data = public(row)
    host = db.get(PlayerWorld, row.world_id)
    data["world_name"] = host.name if host else None
    names = _usernames(db, [row.host_player_id, row.invited_player_id])
    data["host_username"] = names.get(row.host_player_id, "Player")
    data["guest_username"] = names.get(row.invited_player_id, "Player")
    return data


class FarmInvitationService:
    def __init__(self, db):
        self.db = db

    @staticmethod
    def _resolve(row, status):
        """Move an invitation out of PENDING and free its uniqueness key."""
        row.status = status
        row.active_key = None
        row.responded_at = utcnow()

    def invite(self, host_id, guest_id):
        """Host invites one guest. Idempotent on an unexpired open offer."""
        if host_id == guest_id:
            raise AppError("SELF_INTERACTION", "You cannot invite yourself")
        # Deferred: service.py imports this module at module scope.
        from app.modules.social.service import SocialService

        now = utcnow()
        with transaction(self.db):
            SocialService(self.db).allowed(host_id, guest_id)
            world = owned_world(self.db, host_id)
            lock_rows(self.db, host_id, guest_id, world_id=world.id)

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
                    return invitation_public(self.db, existing)
                self._resolve(existing, "EXPIRED")

            row = FarmInvitation(
                host_player_id=host_id,
                invited_player_id=guest_id,
                world_id=world.id,
                status="PENDING",
                active_key=active_key(host_id, guest_id, world.id),
                expires_at=now + INVITE_TTL,
            )
            self.db.add(row)
            self.db.flush()
            NotificationsService(self.db).emit(
                guest_id,
                "farm_invitation",
                f"{_usernames(self.db, [host_id]).get(host_id, 'A player')} invited you to visit their farm",
                f"/farm/invitations/{row.id}",
            )
            result = invitation_public(self.db, row)
        return result

    def _pending_for_party(self, invitation_id, party_column, party_id):
        """Load a PENDING invitation owned by ``party``, or 404.

        The ownership check runs *before* the lock and again after it, so a guest
        can neither resolve somebody else's offer nor learn that its id exists.
        """
        row = self.db.get(FarmInvitation, invitation_id)
        if row is None or getattr(row, party_column) != party_id:
            raise NotFound("Invitation not found")
        lock_rows(
            self.db, *sorted({row.host_player_id, row.invited_player_id}), world_id=row.world_id
        )
        row = self.db.get(FarmInvitation, invitation_id)
        if row.status != "PENDING":
            raise AppError(
                "INVITE_RESOLVED", "This invitation is no longer pending", 409
            )
        return row

    def cancel(self, host_id, invitation_id):
        """Host withdraws an offer. Resolved offers report as already handled."""
        with transaction(self.db):
            row = self._pending_for_party(invitation_id, "host_player_id", host_id)
            self._resolve(row, "CANCELLED")
            result = invitation_public(self.db, row)
        return result

    def decline(self, guest_id, invitation_id):
        """Guest turns the offer down."""
        with transaction(self.db):
            row = self._pending_for_party(invitation_id, "invited_player_id", guest_id)
            self._resolve(row, "DECLINED")
            result = invitation_public(self.db, row)
        return result

    def accept(self, guest_id, invitation_id):
        """Guest accepts: revalidate everything, then reserve a slot atomically.

        Slot admission is transactional, not read-then-write. Counting free slots
        and inserting the visit session happen inside one transaction holding
        ``SELECT ... FOR UPDATE`` on the host's world row, so two guests racing
        for the fifth slot are serialized by the database. The unique
        ``active_visitor_key`` index is the backstop: even if the lock were
        unavailable, the second insert would fail rather than over-fill.

        A rejected accept deliberately leaves the invitation PENDING. Marking it
        resolved before raising would roll back with the exception and either
        write nothing or, worse, consume an invitation because the farm happened
        to be full at that instant. Staying PENDING lets the guest retry once a
        slot frees up, and the expiry sweep still retires a genuinely stale
        offer.
        """
        # Deferred: service.py imports this module at module scope.
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
            lock_rows(self.db, guest_id, host_id, world_id=world_id)
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

            NotificationsService(self.db).emit(
                host_id,
                "farm_visitor_joined",
                f"{_usernames(self.db, [guest_id]).get(guest_id, 'A player')} is visiting your farm",
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