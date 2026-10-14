from sqlalchemy import and_, cast, exists, literal, or_, select, String
from sqlalchemy.orm import aliased

from app.core.clock import utcnow
from app.db.repository import Repository
from app.modules.players.models import Player
from app.modules.realtime.models import MessageRecipient, NearbyMessage, Presence
from app.modules.social.models import FarmVisitSession, PlayerBlock
from app.modules.world.models import CAMPUS_ROOM, PlayerWorld


def authorized_presence(since):
    """Exclude stale/ended visitors even before their socket's next snapshot."""
    host = aliased(Presence)
    visiting = exists(
        select(1).where(
            FarmVisitSession.visitor_player_id == Presence.player_id,
            FarmVisitSession.status == "ACTIVE",
        )
    )
    owns = exists(
        select(1).where(
            PlayerWorld.owner_id == Presence.player_id,
            Presence.room == literal("world:") + cast(PlayerWorld.id, String),
        )
    )
    admitted = exists(
        select(1)
        .select_from(FarmVisitSession)
        .join(host, host.player_id == FarmVisitSession.host_player_id)
        .where(
            FarmVisitSession.visitor_player_id == Presence.player_id,
            FarmVisitSession.status == "ACTIVE",
            Presence.room
            == literal("world:") + cast(FarmVisitSession.world_id, String),
            host.room == Presence.room,
            host.updated_at >= since,
        )
    )
    active_player = exists(
        select(1).where(
            Player.id == Presence.player_id,
            Player.is_active.is_(True),
            Player.email_verified.is_(True),
        )
    )
    return and_(
        active_player,
        or_(
            and_(Presence.room == CAMPUS_ROOM, ~visiting),
            and_(owns, ~visiting),
            admitted,
        ),
    )


class RealtimeRepository(Repository):
    def nearby(self, room, since, x, y, radius):
        return list(
            self.db.scalars(
                select(Presence)
                .where(
                    authorized_presence(since),
                    Presence.room == room,
                    Presence.updated_at >= since,
                    Presence.x.between(x - radius, x + radius),
                    Presence.y.between(y - radius, y + radius),
                )
                .order_by(
                    (
                        (Presence.x - x) * (Presence.x - x)
                        + (Presence.y - y) * (Presence.y - y)
                    ),
                    Presence.player_id,
                )
                .limit(200)
            )
        )

    def blocked_ids(self, pid):
        return set(
            self.db.scalars(
                select(PlayerBlock.blocked_id)
                .where(PlayerBlock.player_id == pid)
                .union(
                    select(PlayerBlock.player_id).where(PlayerBlock.blocked_id == pid)
                )
            )
        )

    def usernames(self, ids):
        return dict(
            self.db.execute(
                select(Player.id, Player.username).where(Player.id.in_(ids))
            ).all()
        )

    def visible_nearby(self, pid, room, x, y, radius, since):
        """Everyone in ``room`` within ``radius`` of (x, y) who can see ``pid``.

        The one place "who is near me, and am I allowed to see them" is
        answered. Both the snapshot roster and the proximity policy view call it,
        so blocked players can never be filtered out of one and left in the other.

        Returns ``(rows, usernames, blocked)``.
        """
        blocked = self.blocked_ids(pid)
        rows = [
            row
            for row in self.nearby(room, since, x, y, radius)
            if row.player_id not in blocked
        ]
        return rows, self.usernames([row.player_id for row in rows]), blocked

    def messages(self, pid, room, room_epoch):
        """Chat this player can still read: their room, their epoch, unexpired.

        The only read in this repository that filters by *receiver* rather than
        by room scope, which is why it takes the player id at all.
        """
        return list(
            self.db.scalars(
                select(NearbyMessage)
                .join(MessageRecipient, MessageRecipient.message_id == NearbyMessage.id)
                .where(
                    MessageRecipient.player_id == pid,
                    MessageRecipient.room_epoch == room_epoch,
                    NearbyMessage.room == room,
                    NearbyMessage.expires_at > utcnow(),
                )
                .order_by(NearbyMessage.id)
                .limit(100)
            )
        )