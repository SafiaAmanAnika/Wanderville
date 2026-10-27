from sqlalchemy import select
from app.core.exceptions import AppError
from app.core.idempotency import ensure_same_payload
from app.core.responses import public
from app.modules.world.service import game_day
from app.core.progression import SELL_XP_PER_UNIT, sells_for_xp
from app.db.session import transaction
from app.modules.shop.models import ItemRule, Purchase, Sale, StarterGrant, CollectionEntry
from app.db.repository import Repository
from app.modules.inventory.models import ItemDefinition
from app.modules.inventory.service import InventoryService
from app.modules.economy.service import EconomyService
from app.modules.players.repository import PlayerRepository
from app.modules.progression.service import ProgressionService

# Every crop in Assets/farming/crop_manifest.json; the art is the source of truth.
ORIGINAL_SEEDS = (
    "paddy", "wheat", "sugarcane", "barley", "oats", "sweet_corn", "zucchini",
    "bell_pepper", "strawberry", "green_bean", "pumpkin", "brussels_sprouts", "kale",
    "apple", "turnip", "potato", "carrot", "cabbage", "spinach", "onion", "lettuce", "pea",
    "radish", "asparagus", "beetroot", "moonflower", "rivermint", "sunbloom",
    "ancient_grain",
)
STARTER_CODE = "original_seeds_v1"
# Balancing choice: two level-one all-season seeds at a workable quantity, so the
# first planting works without overwhelming the shared slot pool.
STARTER_ITEMS = {"paddy_seed": 5, "wheat_seed": 5}


class ShopService:
    def __init__(self, db):
        self.db, self.repo = db, Repository(db)
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
            "starter": self.starter_status(player_id),
            "items": [
                {
                    **public(i),
                    "required_level": r.required_level,
                    "locked": level < r.required_level,
                    "in_stock": self.available(i, day),
                    "partition": r.partition,
                    "harvest_code": r.harvest_code,
                }
                for i, r in rows
            ],
        }

    def buy(self, player_id, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            old = ensure_same_payload(
                self.repo.get(Purchase, (player_id, request.request_id), False),
                {"item_code": request.item_code, "quantity": request.quantity},
                "Request ID was used for another purchase",
            )
            if old:
                return public(old)
            item = self.inventory.definition(request.item_code)
            rule = self.repo.get(ItemRule, item.item_code)
            day = game_day(self.db)
            if not self.available(item, day):
                raise AppError("OUT_OF_STOCK", "Item is not stocked today")
            if self.economy.xp(player_id).level < rule.required_level:
                raise AppError("LEVEL_internal", "Required level has not been reached")
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
            request_id = getattr(request, "request_id", None)
            if request_id:
                old = ensure_same_payload(
                    self.db.get(Sale, (player_id, request_id)),
                    {"item_code": request.item_code, "quantity": request.quantity},
                    "Request ID was used for another sale",
                )
                if old:
                    return {"aura_earned": old.unit_price * old.quantity, "quantity": old.quantity}
            item = self.inventory.definition(request.item_code)
            if item.sell_value <= 0:
                raise AppError("NOT_SELLABLE", "This item has no sell value")
            self.inventory.remove_internal(player_id, item.item_code, request.quantity)
            self.economy.change_internal(
                player_id, item.sell_value * request.quantity, True, "item_sale"
            )
            # Only gathered produce pays XP; store stock cannot be resold for XP.
            if sells_for_xp(item.category):
                self.economy.gain_internal(
                    player_id, SELL_XP_PER_UNIT * request.quantity
                )
            ProgressionService(self.db).record(player_id, "sell")
            if request_id:
                self.db.add(Sale(player_id=player_id, request_id=request_id, item_code=item.item_code,
                                 quantity=request.quantity, unit_price=item.sell_value))
        return {
            "aura_earned": item.sell_value * request.quantity,
            "quantity": request.quantity,
        }

    def transaction_status(self, player_id, request_id, action):
        row = self.db.get(Purchase if action == "buy" else Sale, (player_id, request_id))
        return {"found": row is not None, "receipt": public(row) if row else None}

    def starter_status(self, player_id):
        grant = self.db.get(StarterGrant, (player_id, STARTER_CODE))
        return {"grant_code": STARTER_CODE, "claimed": grant is not None, "items": STARTER_ITEMS}

    def claim_starter(self, player_id):
        # Explicit opt-in for both new and existing accounts. Empty inventory is
        # never an eligibility signal. The durable marker survives consumption.
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            if self.db.get(StarterGrant, (player_id, STARTER_CODE)):
                return {**self.starter_status(player_id), "already_claimed": True}
            for code, quantity in STARTER_ITEMS.items():
                self.inventory.add_internal(player_id, code, quantity)
            self.db.add(StarterGrant(player_id=player_id, grant_code=STARTER_CODE))
        return {"grant_code": STARTER_CODE, "claimed": True, "already_claimed": False, "items": STARTER_ITEMS}

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
