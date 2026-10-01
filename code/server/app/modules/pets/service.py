from app.core.clock import as_utc, utcnow
from app.core.exceptions import AppError
from app.core.gameplay import public
from app.db.session import transaction
from app.modules.pets.models import PlayerPet
from app.modules.pets.repository import PetsRepository
from app.modules.shop.models import ItemRule
from app.modules.inventory.service import InventoryService
from app.modules.players.repository import PlayerRepository


class PetsService:
    def __init__(self, db):
        self.db, self.repo = db, PetsRepository(db)

    def get(self, player_id):
        row = self.repo.get(PlayerPet, player_id)
        return {
            **public(row),
            "resting": row.last_interaction_at is None
            or (utcnow() - as_utc(row.last_interaction_at)).total_seconds() >= 60,
        }

    def act(self, player_id, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.get(PlayerPet, player_id)
            now, inv = utcnow(), InventoryService(self.db)
            if request.action == "rename":
                if not request.name:
                    raise AppError("NAME_REQUIRED", "Enter a pet name")
                row.name = request.name
            elif request.action == "accessory":
                if request.item_code:
                    rule = self.repo.get(ItemRule, request.item_code)
                    if not rule.pet_accessory or not inv.has_item(
                        player_id, request.item_code
                    ):
                        raise AppError(
                            "INVALID_ACCESSORY", "Own a valid pet accessory first"
                        )
                row.accessory_code = request.item_code
            else:
                if (
                    row.last_interaction_at
                    and (now - as_utc(row.last_interaction_at)).total_seconds() < 5
                ):
                    raise AppError(
                        "PET_COOLDOWN",
                        "Wait a few seconds before another interaction",
                        429,
                    )
                gain = 0
                if request.action == "feed":
                    rule = self.repo.get(ItemRule, request.item_code)
                    if not rule.pet_food:
                        raise AppError("INVALID_FOOD", "This is not pet food")
                    inv.remove_internal(player_id, request.item_code)
                    gain = 10
                elif request.action == "pet":
                    gain = 2
                elif request.action == "fetch_start":
                    row.fetch_started_at = now
                elif request.action == "fetch_finish":
                    if (
                        row.fetch_started_at is None
                        or (now - as_utc(row.fetch_started_at)).total_seconds() < 5
                    ):
                        raise AppError(
                            "FETCH_NOT_READY", "Start fetch and allow the pet to return"
                        )
                    row.fetch_started_at = None
                    gain = 3
                row.affection = min(100, row.affection + gain)
                row.last_interaction_at = now
        return self.get(player_id)
