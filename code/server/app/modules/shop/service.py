from sqlalchemy import select
from app.core.exceptions import AppError
from app.core.gameplay import game_day, public
from app.db.session import transaction
from app.modules.shop.models import ItemRule, Purchase, CollectionEntry
from app.modules.shop.repository import ShopRepository
from app.modules.inventory.models import ItemDefinition
from app.modules.inventory.service import InventoryService
from app.modules.economy.service import EconomyService
from app.modules.players.repository import PlayerRepository
from app.modules.progression.service import ProgressionService


class ShopService:
    def __init__(self, db):
        self.db, self.repo = db, ShopRepository(db)
        self.inventory, self.economy = InventoryService(db), EconomyService(db)

    def available(self, item, day):
        # Staple seeds/tools are always stocked; rare stock rotates deterministically.
        return item.buy_value is not None and (
            item.rarity == "common" or (sum(item.item_code.encode()) + day) % 3 == 0
        )

    def catalog(self, player_id):
        day, level = game_day(self.db), self.economy.xp(player_id).level
        rows = self.db.execute(
            select(ItemDefinition, ItemRule)
            .join(ItemRule, ItemRule.item_code == ItemDefinition.item_code)
            .where(ItemDefinition.buy_value.is_not(None))
        ).all()
        return {
            "game_day": day,
            "items": [
                {
                    **public(i),
                    "required_level": r.required_level,
                    "locked": level < r.required_level,
                    "in_stock": self.available(i, day),
                }
                for i, r in rows
            ],
        }

    def buy(self, player_id, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            old = self.repo.get(Purchase, (player_id, request.request_id), False)
            if old:
                if (old.item_code, old.quantity) != (
                    request.item_code,
                    request.quantity,
                ):
                    raise AppError(
                        "IDEMPOTENCY_CONFLICT",
                        "Request ID was used for another purchase",
                        409,
                    )
                return public(old)
            item = self.inventory.definition(request.item_code)
            rule = self.repo.get(ItemRule, item.item_code)
            day = game_day(self.db)
            if not self.available(item, day):
                raise AppError("OUT_OF_STOCK", "Item is not stocked today")
            if self.economy.xp(player_id).level < rule.required_level:
                raise AppError("LEVEL_LOCKED", "Required level has not been reached")
            cost = item.buy_value * request.quantity
            if cost:
                self.economy.change_internal(player_id, cost, False, "shop_purchase")
            self.inventory.add_internal(player_id, item.item_code, request.quantity)
            row = self.repo.add(
                Purchase,
                player_id=player_id,
                request_id=request.request_id,
                item_code=item.item_code,
                quantity=request.quantity,
                unit_price=item.buy_value,
                game_day=day,
            )
        return public(row)

    def sell(self, player_id, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            item = self.inventory.definition(request.item_code)
            if item.sell_value <= 0:
                raise AppError("NOT_SELLABLE", "This item has no sell value")
            self.inventory.remove_internal(player_id, item.item_code, request.quantity)
            self.economy.change_internal(
                player_id, item.sell_value * request.quantity, True, "item_sale"
            )
            self.economy.gain_internal(player_id, 2)
            ProgressionService(self.db).record(player_id, "sell")
        return {
            "aura_earned": item.sell_value * request.quantity,
            "quantity": request.quantity,
        }

    def collection(self, player_id, fish_only=False):
        rows = self.db.execute(
            select(ItemDefinition, CollectionEntry)
            .outerjoin(
                CollectionEntry,
                (CollectionEntry.item_code == ItemDefinition.item_code)
                & (CollectionEntry.player_id == player_id),
            )
            .order_by(ItemDefinition.item_code)
        ).all()
        return [
            {"item_code": i.item_code, "name": i.name, "obtained": e is not None}
            for i, e in rows
            if not fish_only or i.category == "fish"
        ]
