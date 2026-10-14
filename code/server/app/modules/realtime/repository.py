from sqlalchemy import select, exists, cast, String, literal, and_, or_
from app.core.gameplay import Repository
from app.modules.realtime.models import Presence


def authorized_presence(since):
    """Exclude stale/ended visitors even before their socket's next snapshot."""
    from sqlalchemy.orm import aliased
    from app.modules.players.models import Player
    from app.modules.world.models import PlayerWorld
    from app.modules.social.models import FarmVisitSession

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
            and_(Presence.room == "campus", ~visiting), and_(owns, ~visiting), admitted
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
        from app.modules.social.models import PlayerBlock

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
        from app.modules.players.models import Player

        return dict(
            self.db.execute(
                select(Player.id, Player.username).where(Player.id.in_(ids))
            ).all()
        )

    def messages(self, pid, room, room_epoch):
        from app.core.clock import utcnow
        from app.modules.realtime.models import NearbyMessage, MessageRecipient

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
