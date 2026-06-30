from app.database import Base

# Import all models so Alembic can discover them
from app.models.player import Player
from app.models.world import World, WorldState
from app.models.farm import FarmPlot
from app.models.inventory import InventoryItem
from app.models.item import ItemDefinition
from app.models.economy import PlayerEconomy
from app.models.experience import PlayerExperience

__all__ = [
    "Base",
    "Player",
    "World",
    "WorldState",
    "FarmPlot",
    "InventoryItem",
    "ItemDefinition",
    "PlayerEconomy",
    "PlayerExperience",
]