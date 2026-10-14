from sqlalchemy import select

from app.modules.inventory.models import InventoryItem, ItemDefinition
from app.modules.shop.models import ItemRule


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
                .order_by(InventoryItem.item_code, InventoryItem.stack_no)
            )
        )

    def stacks(self, player_id, code, location="inventory"):
        """Every stack of one item, in stable creation order."""
        return list(
            self.db.scalars(
                select(InventoryItem)
                .where(
                    InventoryItem.player_id == player_id,
                    InventoryItem.item_code == code,
                    InventoryItem.location == location,
                )
                .order_by(InventoryItem.stack_no)
                .execution_options(populate_existing=True)
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
            .order_by(InventoryItem.stack_no)
            .execution_options(populate_existing=True)
        )

    def used_slots(self, player_id):
        return len(self.list(player_id))

    def rules(self, codes):
        """Shop rules for many item codes in one query.

        Inventory listing needs the level/season/partition fields of every item
        it is about to return; asking per row turns one page into N+1.
        """
        codes = set(codes)
        if not codes:
            return []
        return list(self.db.scalars(select(ItemRule).where(ItemRule.item_code.in_(codes))))

    def add(self, player_id, code, quantity, location, stack_no=0):
        row = InventoryItem(
            player_id=player_id,
            item_code=code,
            quantity=quantity,
            location=location,
            stack_no=stack_no,
        )
        self.db.add(row)
        self.db.flush()
        return row

    def delete(self, row):
        self.db.delete(row)
        self.db.flush()
