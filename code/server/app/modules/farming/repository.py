from sqlalchemy import select

from app.modules.farming.models import FarmTile


class FarmingRepository:
    def __init__(self, db):
        self.db = db

    def list(self, world_id):
        return list(
            self.db.scalars(
                select(FarmTile)
                .where(FarmTile.world_id == world_id)
                .order_by(FarmTile.y, FarmTile.x)
            )
        )

    def has_active_crops(self):
        return (
            self.db.scalar(
                select(FarmTile.id).where(FarmTile.crop_item_code.is_not(None)).limit(1)
            )
            is not None
        )

    def coordinate(self, world_id, x, y):
        return self.db.scalar(
            select(FarmTile)
            .where(FarmTile.world_id == world_id, FarmTile.x == x, FarmTile.y == y)
            .execution_options(populate_existing=True)
        )

    def by_world_tile(self, world_id, tile_id):
        """Fetch a tile scoped by world only.

        Callers must already have passed the ownership check; the world id comes
        from the world row that check resolved, never from the request body.
        """
        return self.db.scalar(
            select(FarmTile)
            .where(FarmTile.world_id == world_id, FarmTile.id == tile_id)
            .execution_options(populate_existing=True)
        )

    def create(self, world_id, x, y):
        row = FarmTile(world_id=world_id, x=x, y=y)
        self.db.add(row)
        self.db.flush()
        return row
