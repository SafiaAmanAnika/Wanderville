from sqlalchemy import select

from app.modules.players.models import Player


class PlayerRepository:
    def __init__(self, db):
        self.db = db

    def get(self, player_id):
        return self.db.get(Player, player_id)

    def by_username(self, username):
        return self.db.scalar(select(Player).where(Player.username == username))

    def by_email(self, email):
        return self.db.scalar(select(Player).where(Player.email == email))

    def by_oauth(self, provider, subject):
        return self.db.scalar(
            select(Player).where(
                Player.oauth_provider == provider, Player.oauth_provider_id == subject
            )
        )

    def lock(self, *player_ids):
        # Common locking order serializes gameplay and avoids reciprocal-transfer deadlocks.
        return list(
            self.db.scalars(
                select(Player)
                .where(Player.id.in_(player_ids))
                .order_by(Player.id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )
        )

    def create(self, **values):
        player = Player(**values)
        self.db.add(player)
        self.db.flush()
        return player
