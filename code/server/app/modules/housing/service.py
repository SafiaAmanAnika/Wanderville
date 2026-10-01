from app.core.exceptions import AppError, NotFound
from app.core.gameplay import public
from app.db.session import transaction
from app.modules.housing.models import HouseTier, PlayerHouse, Decoration
from app.modules.housing.repository import HousingRepository
from app.modules.players.repository import PlayerRepository
from app.modules.inventory.service import InventoryService
from app.modules.economy.service import EconomyService


class HousingService:
    def __init__(self, db):
        self.db, self.repo = db, HousingRepository(db)

    def get(self, player_id):
        house = self.repo.get(PlayerHouse, player_id)
        return {
            "house": public(house),
            "tiers": [
                public(r) for r in self.repo.list(HouseTier, order=HouseTier.tier)
            ],
            "decorations": [
                public(r)
                for r in self.repo.list(Decoration, Decoration.player_id == player_id)
            ],
        }

    def upgrade(self, player_id, expected_tier):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            house = self.repo.get(PlayerHouse, player_id)
            if house.tier != expected_tier:
                raise AppError(
                    "STALE_HOUSE", "House tier changed; refresh before confirming", 409
                )
            tier = self.repo.get(HouseTier, house.tier + 1, False)
            if tier is None:
                raise AppError("MAX_TIER", "House is fully upgraded")
            economy = EconomyService(self.db)
            if economy.xp(player_id).level < tier.required_level:
                raise AppError("LEVEL_LOCKED", "Required level has not been reached")
            if tier.cost:
                economy.change_internal(player_id, tier.cost, False, "house_upgrade")
            house.tier = tier.tier
        return public(house)

    def place(self, player_id, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            inventory = InventoryService(self.db)
            if not inventory.definition(request.item_code).placeable:
                raise AppError("NOT_PLACEABLE", "This item cannot be placed")
            if (
                len(self.repo.list(Decoration, Decoration.player_id == player_id))
                >= 100
            ):
                raise AppError("DECORATION_LIMIT", "At most 100 outdoor decorations")
            inventory.remove_internal(player_id, request.item_code)
            row = self.repo.add(
                Decoration,
                player_id=player_id,
                item_code=request.item_code,
                x=request.x,
                y=request.y,
            )
        return public(row)

    def remove(self, player_id, decoration_id):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.get(Decoration, decoration_id)
            if row.player_id != player_id:
                raise NotFound()
            InventoryService(self.db).add_internal(player_id, row.item_code)
            self.db.delete(row)
        return {"removed": decoration_id}
