import math
from datetime import timedelta
from app.core.clock import as_utc, utcnow
from app.core.exceptions import AppError
from app.core.gameplay import public
from app.db.session import transaction
from app.modules.realtime.models import Presence, NearbyMessage, MessageRecipient
from app.modules.realtime.repository import RealtimeRepository
from app.modules.players.repository import PlayerRepository
from app.modules.profile.models import PlayerProfile
from app.modules.social.service import SocialService, filter_message


class RealtimeService:
    def __init__(self, db):
        self.db, self.repo = db, RealtimeRepository(db)

    def enter(self, pid, owner_id=None):
        with transaction(self.db):
            PlayerRepository(self.db).lock(*sorted({pid, owner_id or pid}))
            if owner_id and owner_id != pid:
                SocialService(self.db).allowed(pid, owner_id)
            room = f"farm:{owner_id}" if owner_id else "campus"
            row = self.repo.get(Presence, pid, False)
            # Re-entering the same room restores the saved position and sequence.
            if (
                row
                and row.room == room
            ):
                row.updated_at = utcnow()
                return public(row)
            values = dict(
                room=room,
                x=7377.0 if not owner_id else 0.0,
                y=-891.0 if not owner_id else 0.0,
                sequence=0,
                updated_at=utcnow(),
                emote=None,
                emote_until=None,
            )
            if row:
                for k, v in values.items():
                    setattr(row, k, v)
            else:
                row = self.repo.add(Presence, player_id=pid, **values)
        return public(row)

    def active(self, pid):
        row = self.repo.get(Presence, pid)
        if (utcnow() - as_utc(row.updated_at)).total_seconds() > 60:
            raise AppError("SESSION_EXPIRED", "Enter the world again", 409)
        if row.room.startswith("farm:"):
            owner = int(row.room.split(":")[1])
            if owner != pid:
                SocialService(self.db).allowed(pid, owner)
        return row

    def leave(self, pid):
        with transaction(self.db):
            PlayerRepository(self.db).lock(pid)
            row = self.repo.get(Presence, pid, False)
            if row:
                # Retain position for storage but expire its visible presence.
                row.updated_at = utcnow() - timedelta(seconds=61)
            profile = self.db.get(PlayerProfile, pid)
            if profile:
                profile.last_seen_at = utcnow()

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

            if row.room == "campus" and blocked_segment(
                row.x, row.y, request.x, request.y
            ):
                raise AppError("COLLISION", "Movement crosses a blocked campus polygon")
            row.x, row.y, row.sequence, row.updated_at = (
                request.x,
                request.y,
                request.sequence,
                utcnow(),
            )
            self.db.get(PlayerProfile, pid).last_seen_at = row.updated_at
        return public(row)

    def snapshot(self, pid):
        row = self.active(pid)
        blocked = self.repo.blocked_ids(pid)
        nearby = self.repo.nearby(
            row.room, utcnow() - timedelta(seconds=60), row.x, row.y, 2000
        )
        names = self.repo.usernames([r.player_id for r in nearby])
        visible = []
        for other in nearby:
            if other.player_id in blocked:
                continue
            item = public(other)
            item["username"] = names[other.player_id]
            if not other.emote_until or as_utc(other.emote_until) < utcnow():
                item["emote"] = None
            visible.append(item)
        messages = self.repo.messages(pid)
        return {
            "players": visible,
            "messages": [public(m) for m in messages if m.sender_id not in blocked],
            "server_time": utcnow(),
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
                raise AppError(
                    "CHAT_COOLDOWN", "Wait before sending another message", 429
                )
            message = self.repo.add(
                NearbyMessage,
                sender_id=pid,
                body=filter_message(body),
                expires_at=utcnow() + timedelta(seconds=10),
            )
            blocked = self.repo.blocked_ids(pid)
            for other in self.repo.nearby(
                row.room, utcnow() - timedelta(seconds=60), row.x, row.y, 600
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
