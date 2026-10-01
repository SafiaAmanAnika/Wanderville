"""Explicit metadata discovery; no FastAPI or route imports."""

from app.db.base import Base
from app.modules.auth.models import AccountToken, RefreshToken
from app.modules.economy.models import (
    EconomyTransaction,
    PlayerEconomy,
    PlayerExperience,
)
from app.modules.farming.models import FarmTile
from app.modules.inventory.models import InventoryItem, ItemDefinition
from app.modules.players.models import Player
from app.modules.world.models import PlayerWorld, WorldState

__all__ = [
    "Base",
    "Player",
    "AccountToken",
    "RefreshToken",
    "EconomyTransaction",
    "PlayerEconomy",
    "PlayerExperience",
    "FarmTile",
    "InventoryItem",
    "ItemDefinition",
    "PlayerWorld",
    "WorldState",
]
