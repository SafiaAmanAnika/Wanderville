from sqlalchemy import select

from app.modules.world.models import CAMPUS_SPAWN, PlayerWorld, WorldState


class WorldRepository:
    def __init__(self, db):
        self.db = db

    def for_player(self, player_id):
        return self.db.scalar(
            select(PlayerWorld).where(PlayerWorld.owner_id == player_id)
        )

    def by_id(self, world_id):
        return self.db.get(PlayerWorld, world_id)

    def create(self, player_id, name="My World"):
        row = PlayerWorld(
            owner_id=player_id,
            name=name,
            farm_entrance_x=CAMPUS_SPAWN[0],
            farm_entrance_y=CAMPUS_SPAWN[1],
        )
        self.db.add(row)
        self.db.flush()
        return row

    def state(self, lock=False):
        query = select(WorldState).where(WorldState.id == 1)
        if lock:
            query = query.with_for_update().execution_options(populate_existing=True)
        return self.db.scalar(query)
