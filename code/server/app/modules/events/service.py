from app.core.clock import as_utc, utcnow
from app.core.exceptions import AppError
from app.core.gameplay import public
from app.db.session import transaction
from app.modules.events.models import WorldEvent, EventClaim
from app.modules.events.repository import EventsRepository
from app.modules.players.repository import PlayerRepository
from app.modules.inventory.service import InventoryService


class EventsService:
    def __init__(self, db):
        self.db, self.repo = db, EventsRepository(db)

    def list(self):
        now = utcnow()
        return [
            public(r)
            for r in self.repo.list(
                WorldEvent, WorldEvent.starts_at <= now, WorldEvent.ends_at > now
            )
        ]

    def claim(self, player_id, code):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.get(WorldEvent, code)
            if not as_utc(row.starts_at) <= utcnow() < as_utc(row.ends_at):
                raise AppError("EVENT_EXPIRED", "Event is not currently active")
            if self.repo.get(EventClaim, (player_id, code), False):
                raise AppError("ALREADY_CLAIMED", "Event reward already claimed", 409)
            InventoryService(self.db).add_internal(
                player_id, row.item_code, row.quantity
            )
            self.repo.add(EventClaim, player_id=player_id, event_code=code)
        return {"item_code": row.item_code, "quantity": row.quantity}
