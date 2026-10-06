"""Realtime presence, scoped to a world room.

Rooms come in two kinds, and the difference is the whole point:

``campus``
    The pre-existing shared map. It has no persistent per-player world data --
    fishing spots and water sources are keyed by item/spot code, not by world --
    so it stays a shared room exactly as before.

``world:{world_id}``
    A persistent world. Used for a player's own farm, and for the farm of
    somebody they are currently visiting. The key names the *world*, not the
    owner, so "I am standing in world 7" stops implying "I own world 7".

A caller cannot choose a room by asking for it. ``enter`` derives the room from
the server-held session: an ACTIVE visit session sends them to that host's
world, otherwise they land on the campus (or, on request, their own world).
Naming somebody else's world as a visitor is rejected -- the only way into
another farm is an accepted invitation.

Snapshot reads are scoped by the caller's own room row, so a player can only ever
receive presence for the room they are standing in. Movement is validated against
the same room, and a visitor spawns from the host world's entrance rather than
their own coordinates, so a visitor cannot be walked out of the farm or into the
host's tile space by a forged coordinate packet.

Two properties this module deliberately keeps from the existing design:

* Realtime presence stays **ephemeral**. ``player_presence`` is a transient
  position cache used to bootstrap a reconnect; it is not farm state, and no
  walking step is written to the persistent farm tables.
* Broadcasting stays **pull-based** rather than becoming a push fan-out. A
  client already receives a full authoritative snapshot per tick, scoped to its
  own room, which gives the same isolation guarantee as a per-room broadcast
  without a second transport and a second staleness problem.
"""

import math
from datetime import timedelta

from app.core.clock import as_utc, utcnow
from app.core.exceptions import AppError, Forbidden
from app.core.gameplay import public
from app.db.session import transaction
from app.modules.players.repository import PlayerRepository
from app.modules.profile.models import PlayerProfile
from app.modules.realtime.models import MessageRecipient, NearbyMessage, Presence
from app.modules.realtime.repository import RealtimeRepository
from app.modules.social.service import filter_message
from app.modules.world.access import owned_world, resolve
from app.modules.world.models import CAMPUS_SPAWN

CAMPUS_ROOM = "campus"
# How long since the last presence write before a player counts as offline.
PRESENCE_TTL_SECONDS = 60


def world_room(world_id):
    return f"world:{world_id}"


def is_world_room(room):
    return room.startswith("world:")


def room_world_id(room):
    return int(room.split(":", 1)[1])


class RealtimeService:
    def __init__(self, db):
        self.db, self.repo = db, RealtimeRepository(db)

    # ------------------------------------------------------------- entering

    def own_room(self, player_id):
        """The room for this player's own persistent world."""
        return world_room(owned_world(self.db, player_id).id)

    def room_for(self, session, owner_id=None):
        """Resolve the room this session belongs in. Never trusts the request.

        * an ACTIVE visit session wins, because the server already decided this
          player is standing in somebody else's farm;
        * otherwise ``owner_id == player_id`` means "my own farm";
        * otherwise, naming a *different* player is refused, since friendship
          alone must not be a key to another player's world;
        * otherwise the shared campus, which is what an unaffiliated player gets.
        """
        if session.is_visitor:
            if owner_id not in (None, session.host_player_id):
                raise Forbidden("Leave your current farm before visiting another farm")
            return world_room(session.current_world_id)
        if owner_id == session.player_id:
            return world_room(session.owned_world_id)
        if owner_id is not None:
            raise Forbidden("Accept a farm invitation before visiting")
        return CAMPUS_ROOM

    def enter(self, pid, owner_id=None):
        """Join the realtime room the server says this caller belongs in."""
        from app.modules.social.farm_visiting import FarmVisitService

        with transaction(self.db):
            session = resolve(self.db, pid)
            room = self.room_for(session, owner_id)

            row = self.repo.get(Presence, pid, False)
            if row and row.room == room:
                # Re-entering the same room restores the saved position and
                # sequence, which is what makes a reconnect seamless.
                row.updated_at = utcnow()
                FarmVisitService(self.db).heartbeat_locked(pid)
                return self._presence_public(row, session)

            x, y = self.spawn_for(room)
            values = dict(
                room=room,
                x=x,
                y=y,
                sequence=0,
                updated_at=utcnow(),
                emote=None,
                emote_until=None,
            )
            if row:
                for key, value in values.items():
                    setattr(row, key, value)
            else:
                row = self.repo.add(Presence, player_id=pid, **values)
            FarmVisitService(self.db).heartbeat_locked(pid)
            result = self._presence_public(row, session)
        return result

    def spawn_for(self, room):
        """Where a player appears in ``room``.

        A visitor uses the host world's own entrance, never their own farm's
        coordinates; that is what stops a visitor spawning inside the host's
        buildings or outside the map.
        """
        if not is_world_room(room):
            return CAMPUS_SPAWN
        from app.modules.world.repository import WorldRepository

        world = WorldRepository(self.db).by_id(room_world_id(room))
        if world is None:
            return 0.0, 0.0
        return world.farm_entrance_x, world.farm_entrance_y

    def _presence_public(self, row, session=None):
        """Public presence row, annotated with the caller's own session when known.

        ``session`` is passed only for the caller's own row. It is never resolved
        on demand here: doing so once per visible player turned the snapshot into
        an N+1 query fan-out and blew the per-frame statement budget.
        """
        data = public(row)
        if session is not None:
            data["session_mode"] = session.session_mode
            data["owned_world_id"] = session.owned_world_id
            data["current_world_id"] = session.current_world_id
            data["host_player_id"] = session.host_player_id
        return data

    # ------------------------------------------------------------- reading

    def active(self, pid):
        row = self.repo.get(Presence, pid)
        if (utcnow() - as_utc(row.updated_at)).total_seconds() > PRESENCE_TTL_SECONDS:
            raise AppError("SESSION_EXPIRED", "Enter the world again", 409)
        if is_world_room(row.room):
            session = resolve(self.db, pid)
            # A visitor may only hold presence in the world they are visiting.
            # If the session was closed server-side (kick, host offline, sweep)
            # while their socket was still up, their room no longer matches, and
            # this is the frame that tells the client to come back out.
            if row.room != world_room(session.current_world_id):
                raise AppError(
                    "VISIT_ENDED",
                    "You are no longer visiting this farm",
                    409,
                )
        return row

    def leave(self, pid, evict_visitors=True):
        """Release presence and every visit slot tied to this connection.

        Called on socket teardown and on logout. Because a disconnect ends the
        visit from *both* sides, this also reclaims the slots of everyone who was
        standing in this player's farm, using the same code path an explicit
        Leave Farm uses -- so closing a tab frees slots exactly like the button.
        """
        from app.modules.social.farm_visiting import FarmVisitService

        with transaction(self.db):
            if evict_visitors:
                FarmVisitService(self.db).close_all_for_disconnect_locked(pid)
            else:
                FarmVisitService(self.db).leave_locked(pid, "DISCONNECTED")
            row = self.repo.get(Presence, pid, False)
            if row:
                # Retain the last position for reconnect, but expire the visible
                # presence so other players stop seeing a ghost.
                row.updated_at = utcnow() - timedelta(seconds=PRESENCE_TTL_SECONDS + 1)
            profile = self.db.get(PlayerProfile, pid)
            if profile:
                profile.last_seen_at = utcnow()

    # ------------------------------------------------------------- movement

    def move(self, pid, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(pid)
            row = self.active(pid)
            if request.sequence <= row.sequence:
                raise AppError("STALE_MOVEMENT", "Movement sequence must increase", 409)
            elapsed = min(
                1.0, max(0.0, (utcnow() - as_utc(row.updated_at)).total_seconds())
            )
            from app.core.config import settings

            if (
                math.hypot(request.x - row.x, request.y - row.y)
                > settings.max_move_speed * elapsed + 5
            ):
                raise AppError("MOVEMENT_TOO_FAST", "Movement exceeds allowed speed")
            from app.modules.world.geometry import blocked_segment

            if row.room == CAMPUS_ROOM and blocked_segment(
                row.x, row.y, request.x, request.y
            ):
                raise AppError("COLLISION", "Movement crosses a blocked campus polygon")
            row.x, row.y, row.sequence, row.updated_at = (
                request.x,
                request.y,
                request.sequence,
                utcnow(),
            )
            # last_seen_at is a login-activity marker, not a per-step write.
            if self.db.get(PlayerProfile, pid):
                self.db.get(PlayerProfile, pid).last_seen_at = row.updated_at
        return public(row)

    def snapshot(self, pid):
        """Authoritative view of the room the caller is standing in.

        Presence is filtered by the caller's own room on the server, so the
        response cannot contain a player from another farm even if the client
        asked for one.

        The frame is a hot path: it runs several times a second per socket. The
        session is resolved exactly once and the heartbeat only writes when the
        caller is actually a visitor, so an ordinary player pays no extra
        statements per frame.
        """
        from app.modules.social.farm_visiting import FarmVisitService

        row = self.repo.get(Presence, pid)
        if (utcnow() - as_utc(row.updated_at)).total_seconds() > PRESENCE_TTL_SECONDS:
            raise AppError("SESSION_EXPIRED", "Enter the world again", 409)
        session = resolve(self.db, pid)
        if is_world_room(row.room) and row.room != world_room(session.current_world_id):
            # The session was closed server-side (kick, host offline, sweep)
            # while this socket was still up. This frame is what tells the client
            # to come back out of the farm.
            raise AppError("VISIT_ENDED", "You are no longer visiting this farm", 409)
        if session.is_visitor:
            # Owns its transaction: this frame's session is rolled back when the
            # socket loop finishes, so a flush-only write would never reach the
            # database and the stale sweep would reclaim a live visitor.
            with transaction(self.db):
                FarmVisitService(self.db).heartbeat_locked(pid)
        blocked = self.repo.blocked_ids(pid)
        nearby = self.repo.nearby(
            row.room,
            utcnow() - timedelta(seconds=PRESENCE_TTL_SECONDS),
            row.x,
            row.y,
            2000,
        )
        names = self.repo.usernames([r.player_id for r in nearby])
        visible = []
        for other in nearby:
            if other.player_id in blocked:
                continue
            item = self._presence_public(
                other, session if other.player_id == pid else None
            )
            item["username"] = names[other.player_id]
            if not other.emote_until or as_utc(other.emote_until) < utcnow():
                item["emote"] = None
            visible.append(item)
        messages = self.repo.messages(pid)
        return {
            "players": visible,
            "messages": [public(m) for m in messages if m.sender_id not in blocked],
            "server_time": utcnow(),
            "room": row.room,
            "session": session.public(),
        }

    def chat(self, pid, body):
        with transaction(self.db):
            PlayerRepository(self.db).lock(pid)
            row = self.active(pid)
            recent = self.repo.list(
                NearbyMessage,
                NearbyMessage.sender_id == pid,
                NearbyMessage.expires_at > utcnow() + timedelta(seconds=9),
                limit=1,
            )
            if recent:
                raise AppError("CHAT_COOLDOWN", "Wait before sending another message", 429)
            message = self.repo.add(
                NearbyMessage,
                sender_id=pid,
                body=filter_message(body),
                expires_at=utcnow() + timedelta(seconds=10),
            )
            blocked = self.repo.blocked_ids(pid)
            for other in self.repo.nearby(
                row.room,
                utcnow() - timedelta(seconds=PRESENCE_TTL_SECONDS),
                row.x,
                row.y,
                600,
            ):
                if (
                    math.hypot(row.x - other.x, row.y - other.y) <= 600
                    and other.player_id not in blocked
                ):
                    self.db.add(
                        MessageRecipient(
                            message_id=message.id, player_id=other.player_id
                        )
                    )
        return {"message_id": message.id}

    def emote(self, pid, emote):
        with transaction(self.db):
            PlayerRepository(self.db).lock(pid)
            row = self.active(pid)
            row.emote, row.emote_until = emote, utcnow() + timedelta(seconds=3)
        return {"emote": emote}