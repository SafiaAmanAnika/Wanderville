from app.core.config import settings
from app.core.exceptions import AppError, Forbidden, NotFound
from app.db.session import transaction
from app.modules.inventory.repository import InventoryRepository
from app.modules.inventory.schemas import (
    InventoryItemResponse,
    InventoryListResponse,
    ItemDefinitionResponse,
)
from app.modules.players.repository import PlayerRepository


class InventoryService:
    def __init__(self, db):
        self.db, self.repo, self.players = (
            db,
            InventoryRepository(db),
            PlayerRepository(db),
        )

    def definition(self, code):
        item = self.repo.definition(code)
        if item is None:
            raise AppError("INVALID_ITEM", "Item does not exist in the catalog")
        return item

    def list(self, player_id):
        from sqlalchemy import select
        from app.modules.shop.models import ItemRule

        rows = self.repo.list(player_id)
        rules = dict(self.db.execute(select(ItemRule.item_code, ItemRule.partition)).all())
        counts = {name: 0 for name in sorted(set(rules.values()))}
        items = []
        for row in rows:
            item = InventoryItemResponse.model_validate(row)
            item.partition = rules.get(row.item_code)
            if item.partition:
                counts[item.partition] += 1
            items.append(item)
        return InventoryListResponse(
            items=items,
            total_items=len(rows),
            total_quantity=sum(r.quantity for r in rows),
            partition_capacity=settings.inventory_partition_slots,
            partitions=counts,
        )

    def catalog(self, season=None):
        if season and season not in {"spring", "summer", "autumn", "winter", "all"}:
            raise AppError("INVALID_SEASON", "Unknown season")
        return [
            ItemDefinitionResponse.model_validate(r) for r in self.repo.catalog(season)
        ]

    @staticmethod
    def validate_quantity(quantity, location):
        if type(quantity) is not int or not 0 < quantity <= 1_000_000:
            raise AppError(
                "INVALID_QUANTITY", "Quantity must be a positive integer up to 1000000"
            )
        if location != "inventory":
            raise AppError("INVALID_LOCATION", "Only inventory storage is supported")

    def add_internal(self, player_id, code, quantity=1, location="inventory"):
        """Caller owns transaction and player locks. Never commits."""
        self.validate_quantity(quantity, location)
        item = self.definition(code)
        row = self.repo.stack(player_id, code, location)
        if (row.quantity if row else 0) + quantity > item.max_stack:
            raise AppError("INVENTORY_FULL", "Item stack capacity would be exceeded")
        from sqlalchemy import func, select
        from app.modules.shop.models import ItemRule, CollectionEntry
        from app.modules.inventory.models import InventoryItem

        rule = self.db.get(ItemRule, code)
        if row is None and rule:
            count = self.db.scalar(
                select(func.count())
                .select_from(InventoryItem)
                .join(ItemRule, ItemRule.item_code == InventoryItem.item_code)
                .where(
                    InventoryItem.player_id == player_id,
                    ItemRule.partition == rule.partition,
                )
            )
            if count >= settings.inventory_partition_slots:
                raise AppError("INVENTORY_FULL", "Inventory partition is full")
        if row:
            row.quantity += quantity
            self.db.flush()
        else:
            row = self.repo.add(player_id, code, quantity, location)
        if self.db.get(CollectionEntry, (player_id, code)) is None:
            self.db.add(CollectionEntry(player_id=player_id, item_code=code))
            self.db.flush()
        return row

    def remove_internal(self, player_id, code, quantity=1, location="inventory"):
        self.validate_quantity(quantity, location)
        self.definition(code)
        row = self.repo.stack(player_id, code, location)
        if not row or row.quantity < quantity:
            raise AppError("INSUFFICIENT_INVENTORY", "Not enough items in inventory")
        if row.quantity == quantity:
            from app.modules.pets.models import PlayerPet

            pet = self.db.get(PlayerPet, player_id)
            if pet and pet.accessory_code == code:
                pet.accessory_code = None
            self.repo.delete(row)
            return None
        row.quantity -= quantity
        self.db.flush()
        return row

    def has_item(self, player_id, code, quantity=1):
        self.validate_quantity(quantity, "inventory")
        row = self.repo.stack(player_id, code)
        return row is not None and row.quantity >= quantity

    def add_compatibility(self, player_id, request):
        if not settings.is_development:
            raise Forbidden("Arbitrary inventory awards are development-only")
        with transaction(self.db):
            self.players.lock(player_id)
            row = self.add_internal(
                player_id, request.item_code, request.quantity, request.location
            )
            result = InventoryItemResponse.model_validate(row)
        return result

    def remove(self, player_id, request, use=False):
        with transaction(self.db):
            self.players.lock(player_id)
            item = self.definition(request.item_code)
            if (
                not use
                and (item.rarity != "common" or item.sell_value >= 50)
                and not request.confirmed
            ):
                raise AppError(
                    "CONFIRMATION_REQUIRED",
                    "Confirm discarding a rare or high-value item",
                )
            if use and not item.usable:
                raise AppError("ITEM_NOT_USABLE", "This item cannot be used directly")
            row = self.remove_internal(
                player_id, request.item_code, request.quantity, request.location
            )
            result = InventoryItemResponse.model_validate(row) if row else None
        return result

    def transfer(self, player_id, request):
        with transaction(self.db):
            receiver = self.players.by_username(request.to_player_username)
            if receiver is None:
                raise NotFound("Recipient not found")
            if receiver.id == player_id:
                raise AppError("INVALID_TRANSFER", "Cannot transfer to yourself")
            self.players.lock(player_id, receiver.id)
            if not receiver.is_active or not receiver.email_verified:
                raise Forbidden("Recipient is not active")
            from app.modules.social.service import SocialService

            if SocialService(self.db).blocked(player_id, receiver.id):
                raise Forbidden("Interaction is blocked")
            if not self.definition(request.item_code).tradable:
                raise Forbidden("This item cannot be transferred")
            self.remove_internal(player_id, request.item_code, request.quantity)
            self.add_internal(receiver.id, request.item_code, request.quantity)
        return {
            "transferred": request.item_code,
            "item_code": request.item_code,
            "quantity": request.quantity,
            "to": request.to_player_username,
        }
