from sqlalchemy import select

from app.modules.economy.models import (
    EconomyTransaction,
    PlayerEconomy,
    PlayerExperience,
)


class EconomyRepository:
    def __init__(self, db):
        self.db = db

    def economy(self, player_id):
        return self.db.get(PlayerEconomy, player_id, populate_existing=True)

    def experience(self, player_id):
        return self.db.get(PlayerExperience, player_id, populate_existing=True)

    def create(self, player_id):
        self.db.add_all(
            [PlayerEconomy(player_id=player_id), PlayerExperience(player_id=player_id)]
        )
        self.db.flush()

    def record(self, **values):
        row = EconomyTransaction(**values)
        self.db.add(row)
        self.db.flush()
        return row

    def history(self, player_id, limit):
        return list(
            self.db.scalars(
                select(EconomyTransaction)
                .where(EconomyTransaction.player_id == player_id)
                .order_by(EconomyTransaction.id.desc())
                .limit(limit)
            )
        )
