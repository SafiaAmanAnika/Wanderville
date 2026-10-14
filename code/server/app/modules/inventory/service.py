from sqlalchemy import select

from app.core.config import settings
from app.core.exceptions import AppError, Forbidden, NotFound
from app.core.progression import effective_capacity, level_for_xp, slot_capacity
from app.db.session import transaction
from app.modules.economy.repository import EconomyRepository
from app.modules.inventory.repository import InventoryRepository
from app.modules.inventory.schemas import (
    InventoryItemResponse,
    InventoryListResponse,
    ItemDefinitionResponse,
)
from app.modules.players.repository import PlayerRepository
from app.modules.pets.models import PlayerPet
from app.modules.shop.models import CollectionEntry, ItemRule


class InventoryService:
    def __init__(self, db):
        self.db, self.repo, self.players = (
            db,
            InventoryRepository(db),
            PlayerRepository(db),
        )
        self.economy_repo = EconomyRepository(db)

    def definition(self, code):
        item = self.repo.definition(code)
        if item is None:
            raise AppError("INVALID_ITEM", "Item does not exist in the catalog")
        return item

    def level(self, player_id):
        """Current level, falling back to level 1 before XP exists."""
        experience = self.economy_repo.experience(player_id)
        if experience is None:
            return 1
        return level_for_xp(experience.total_xp).level

    def capacity(self, player_id):
        """Shared slot pool: base capacity plus level increments, never below
        what the player already fills."""
        used = self.repo.used_slots(player_id)
        return effective_capacity(self.level(player_id), used, self.base_capacity(player_id))

    def base_capacity(self, player_id):
        experience = self.economy_repo.experience(player_id)
        return experience.inventory_base_capacity if experience else settings.inventory_partition_slots

    def response_for(self, row, rule=None):
        """One row payload, with the harvest fields lifted out of `item`.

        ``rule`` is the item's shop rule when the caller already has it. Passing
        it in is what keeps a full inventory listing from issuing one extra
        query per row; omit it only for a single row whose rule was never fetched.
        """
        result = InventoryItemResponse.model_validate(row)
        result.max_stack = row.item.max_stack
        result.harvest_category = row.item.harvest_category
        result.harvest_xp = row.item.harvest_xp
        if rule is None:
            rule = self.db.scalar(
                select(ItemRule).where(ItemRule.item_code == row.item_code)
            )
        if rule:
            result.partition = rule.partition
            result.required_level = rule.required_level
            result.harvest_code = rule.harvest_code
        return result

    def list(self, player_id):
        rows = self.repo.list(player_id)
        # One lookup for the whole page rather than one per row.
        rules = {
            rule.item_code: rule
            for rule in self.repo.rules([row.item_code for row in rows])
        }
        items = [self.response_for(row, rules.get(row.item_code)) for row in rows]
        level = self.level(player_id)
        return InventoryListResponse(
            items=items,
            total_items=len(rows),
            total_quantity=sum(r.quantity for r in rows),
            capacity=self.capacity(player_id),
            used_slots=len(rows),
            base_capacity=self.base_capacity(player_id),
            level_slots=slot_capacity(level, 0),
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
        """Caller owns transaction and player locks. Never commits.

        Fills existing partial stacks first, then opens new ones. Every new
        stack costs one slot from the shared pool.
        """
        self.validate_quantity(quantity, location)
        item = self.definition(code)
        remaining = quantity
        touched = None
        for row in self.repo.stacks(player_id, code, location):
            if remaining <= 0:
                break
            room = item.max_stack - row.quantity
            if room <= 0:
                continue
            moved = min(room, remaining)
            row.quantity += moved
            remaining -= moved
            touched = row
        self.db.flush()
        if remaining:
            used = self.repo.used_slots(player_id)
            capacity = effective_capacity(
                self.level(player_id), used, self.base_capacity(player_id)
            )
            slots_needed = -(-remaining // item.max_stack)
            if used + slots_needed > capacity:
                raise AppError(
                    "INVENTORY_FULL",
                    "Inventory slots are full; sell or deliver an item to free one",
                )
            stack_no = max(
                (row.stack_no for row in self.repo.stacks(player_id, code, location)),
                default=-1,
            )
            for _ in range(slots_needed):
                stack_no += 1
                touched = self.repo.add(
                    player_id, code, min(remaining, item.max_stack), location, stack_no
                )
                remaining -= touched.quantity
        if self.db.get(CollectionEntry, (player_id, code)) is None:
            self.db.add(CollectionEntry(player_id=player_id, item_code=code))
            self.db.flush()
        return touched

    def remove_internal(self, player_id, code, quantity=1, location="inventory"):
        self.validate_quantity(quantity, location)
        self.definition(code)
        stacks = self.repo.stacks(player_id, code, location)
        if sum(row.quantity for row in stacks) < quantity:
            raise AppError("INSUFFICIENT_INVENTORY", "Not enough items in inventory")
        remaining = quantity
        last = None
        for row in stacks:
            if remaining <= 0:
                break
            taken = min(row.quantity, remaining)
            row.quantity -= taken
            remaining -= taken
            last = row
            if row.quantity == 0:
                pet = self.db.get(PlayerPet, player_id)
                if pet and pet.accessory_code == code and sum(s.quantity for s in stacks) == 0:
                    pet.accessory_code = None
                self.repo.delete(row)
        self.db.flush()
        return last if last is not None and last.quantity > 0 else None

    def has_item(self, player_id, code, quantity=1):
        self.validate_quantity(quantity, "inventory")
        rows = self.repo.stacks(player_id, code)
        return sum(row.quantity for row in rows) >= quantity

    def add_compatibility(self, player_id, request):
        if not settings.is_development:
            raise Forbidden("Arbitrary inventory awards are development-only")
        with transaction(self.db):
            self.players.lock(player_id)
            row = self.add_internal(
                player_id, request.item_code, request.quantity, request.location
            )
            result = self.response_for(row)
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
            result = self.response_for(row) if row else None
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
            # Deferred: social.service imports this module at module scope.
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
