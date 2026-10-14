from sqlalchemy import or_
from app.db.repository import Repository
from app.modules.social.models import Gift, Trade, PlayerBlock


class SocialRepository(Repository):
    def inbox(self, player_id, before=None):
        rows, _ = self.keyset_page(
            Gift,
            Gift.receiver_id == player_id,
            Gift.claimed.is_(False),
            before=before,
            limit=50,
            order=Gift.id.desc(),
        )
        return rows

    def trades(self, player_id):
        return self.list(
            Trade,
            or_(Trade.sender_id == player_id, Trade.receiver_id == player_id),
            Trade.status == "pending",
            limit=100,
            order=Trade.id.desc(),
        )

    def blocks(self, player_id):
        return self.list(PlayerBlock, PlayerBlock.player_id == player_id)
