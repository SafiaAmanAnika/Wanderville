from sqlalchemy import select

from app.modules.inventory.models import InventoryItem, ItemDefinition


class InventoryRepository:
    def __init__(self, db):
        self.db = db

    def definition(self, code):
        return self.db.scalar(
            select(ItemDefinition).where(ItemDefinition.item_code == code)
        )

    def catalog(self, season=None):
        query = select(ItemDefinition).order_by(
            ItemDefinition.category, ItemDefinition.name
        )
        if season:
            query = query.where(ItemDefinition.season.in_([season, "all"]))
        return list(self.db.scalars(query))

    def list(self, player_id):
        return list(
            self.db.scalars(
                select(InventoryItem)
                .where(InventoryItem.player_id == player_id)
                .order_by(InventoryItem.item_code)
            )
        )

    def stack(self, player_id, code, location="inventory"):
        return self.db.scalar(
            select(InventoryItem)
            .where(
                InventoryItem.player_id == player_id,
                InventoryItem.item_code == code,
                InventoryItem.location == location,
            )
            .execution_options(populate_existing=True)
        )

    def add(self, player_id, code, quantity, location):
        row = InventoryItem(
            player_id=player_id, item_code=code, quantity=quantity, location=location
        )
        self.db.add(row)
        self.db.flush()
        return row

    def delete(self, row):
        self.db.delete(row)
        self.db.flush()
