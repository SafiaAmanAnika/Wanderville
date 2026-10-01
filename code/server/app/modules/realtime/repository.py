from sqlalchemy import select
from app.core.gameplay import Repository
from app.modules.realtime.models import Presence


class RealtimeRepository(Repository):
    def nearby(self, room, since, x, y, radius):
        return list(
            self.db.scalars(
                select(Presence)
                .where(
                    Presence.room == room,
                    Presence.updated_at >= since,
                    Presence.x.between(x - radius, x + radius),
                    Presence.y.between(y - radius, y + radius),
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

    def messages(self, pid):
        from app.core.clock import utcnow
        from app.modules.realtime.models import NearbyMessage, MessageRecipient

        return list(
            self.db.scalars(
                select(NearbyMessage)
                .join(MessageRecipient, MessageRecipient.message_id == NearbyMessage.id)
                .where(
                    MessageRecipient.player_id == pid,
                    NearbyMessage.expires_at > utcnow(),
                )
                .order_by(NearbyMessage.id)
                .limit(100)
            )
        )
