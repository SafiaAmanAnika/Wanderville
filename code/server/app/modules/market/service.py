from sqlalchemy import or_
from app.core.exceptions import AppError
from app.core.responses import public
from app.db.repository import Repository
from app.db.session import transaction
from app.modules.market.models import PlayerShop, ShopListing, ShopSale
from app.modules.economy.service import EconomyService
from app.modules.inventory.service import InventoryService
from app.modules.players.repository import PlayerRepository
from app.modules.social.models import Friendship


class MarketService:
    def __init__(self, db):
        self.db, self.repo = db, Repository(db)
        self.inventory, self.economy = InventoryService(db), EconomyService(db)

    # ── helpers ──────────────────────────────────────────────────────

    def _shop_of(self, player_id, required=False):
        rows = self.repo.list(PlayerShop, PlayerShop.owner_id == player_id, limit=1)
        if not rows and required:
            raise AppError("NO_SHOP", "You do not own a shop yet", 404)
        return rows[0] if rows else None

    def _listing(self, shop_id, item_code):
        rows = self.repo.list(
            ShopListing,
            ShopListing.shop_id == shop_id,
            ShopListing.item_code == item_code,
            limit=1,
        )
        return rows[0] if rows else None

    # ── shops ────────────────────────────────────────────────────────

    def mine(self, player_id):
        row = self._shop_of(player_id)
        return public(row) if row else None

    def open(self, player_id, payload):
        with transaction(self.db):
            if self._shop_of(player_id):
                raise AppError("SHOP_EXISTS", "You already own a shop", 409)
            return public(
                self.repo.add(
                    PlayerShop,
                    owner_id=player_id,
                    option_id=payload.option_id,
                    side=payload.side,
                    name=payload.name,
                )
            )

    def friends_shops(self, player_id):
        links = self.repo.list(
            Friendship,
            or_(Friendship.low_id == player_id, Friendship.high_id == player_id),
            Friendship.status == "accepted",
            limit=200,
        )
        ids = [r.high_id if r.low_id == player_id else r.low_id for r in links]
        if not ids:
            return []
        shops = self.repo.list(PlayerShop, PlayerShop.owner_id.in_(ids), limit=200)
        return [public(s) for s in shops]

    # ── listings ─────────────────────────────────────────────────────

    def listings(self, shop_id):
        rows = self.repo.list(ShopListing, ShopListing.shop_id == shop_id, limit=200)
        return [public(r) for r in rows]

    def stock(self, player_id, payload):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            shop = self._shop_of(player_id, True)
            self.inventory.remove_internal(player_id, payload.item_code, payload.quantity)
            row = self._listing(shop.id, payload.item_code)
            if row:
                row.quantity += payload.quantity
                row.price = payload.price
            else:
                row = self.repo.add(
                    ShopListing,
                    shop_id=shop.id,
                    item_code=payload.item_code,
                    quantity=payload.quantity,
                    price=payload.price,
                )
            return public(row)

    def unstock(self, player_id, payload):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            shop = self._shop_of(player_id, True)
            row = self._listing(shop.id, payload.item_code)
            if row is None or row.quantity < payload.quantity:
                raise AppError("SHOP_STOCK", "Not that many on the shelf", 409)
            row.quantity -= payload.quantity
            self.inventory.add_internal(player_id, payload.item_code, payload.quantity)
            if row.quantity == 0:
                self.db.delete(row)
                return None
            return public(row)

    # ── buying ───────────────────────────────────────────────────────

    def buy(self, player_id, payload):
        with transaction(self.db):
            shop = self.repo.get(PlayerShop, payload.shop_id)
            if shop.owner_id == player_id:
                raise AppError("SHOP_OWN", "You cannot buy from your own shop", 409)
            PlayerRepository(self.db).lock(player_id, shop.owner_id)
            row = self._listing(shop.id, payload.item_code)
            if row is None or row.quantity < payload.quantity:
                raise AppError("SHOP_STOCK", "Not enough stock", 409)
            total = row.price * payload.quantity
            self.economy.change_internal(player_id, total, False, "market_purchase")
            self.economy.change_internal(shop.owner_id, total, True, "market_sale")
            self.inventory.add_internal(player_id, payload.item_code, payload.quantity)
            row.quantity -= payload.quantity
            sale = self.repo.add(
                ShopSale,
                shop_id=shop.id,
                buyer_id=player_id,
                item_code=payload.item_code,
                quantity=payload.quantity,
                price=row.price,
            )
            if row.quantity == 0:
                self.db.delete(row)
            return public(sale)

    def sales(self, shop_id):
        rows = self.repo.list(
            ShopSale, ShopSale.shop_id == shop_id, limit=100, order=ShopSale.id.desc()
        )
        return [public(r) for r in rows]