from sqlalchemy import or_
from app.core.gameplay import Repository
from app.modules.social.models import Gift, Trade, Invite, PlayerBlock


class SocialRepository(Repository):
    def inbox(self, player_id, before=None):
        filters = [Gift.receiver_id == player_id, Gift.claimed.is_(False)]
        if before:
            filters.append(Gift.id < before)
        return self.list(Gift, *filters, limit=50, order=Gift.id.desc())

    def trades(self, player_id):
        return self.list(
            Trade,
            or_(Trade.sender_id == player_id, Trade.receiver_id == player_id),
            Trade.status == "pending",
            limit=100,
            order=Trade.id.desc(),
        )

    def invites(self, player_id):
        return self.list(
            Invite,
            or_(Invite.sender_id == player_id, Invite.receiver_id == player_id),
            limit=100,
            order=Invite.id.desc(),
        )

    def blocks(self, player_id):
        return self.list(PlayerBlock, PlayerBlock.player_id == player_id)
