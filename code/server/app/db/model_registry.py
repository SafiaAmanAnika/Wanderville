"""Explicit metadata discovery; no FastAPI or route imports.

SQLAlchemy discovers tables only for modules that are actually imported, so this
file is the single place that guarantees every model in the schema is registered
before ``Base.metadata`` is used to create, migrate, or drop anything. Alembic's
``env.py`` and the seeding commands both import this module for that reason.

Keep it alphabetically grouped by module and keep ``__all__`` in step: an export
list that names only some of the registered models reads as authoritative while
silently omitting tables, which is exactly the failure this file exists to make
impossible.
"""

from app.db.base import Base
from app.modules.auth.models import AccountToken, RefreshToken
from app.modules.economy.models import (
    EconomyTransaction,
    PlayerEconomy,
    PlayerExperience,
    PlayerLevelReward,
)
from app.modules.events.models import EventClaim, WorldEvent
from app.modules.market.models import PlayerShop, ShopListing, ShopSale
from app.modules.farming.models import FarmTile
from app.modules.fishing.models import FishingSession, FishingSpot, GroundDrop
from app.modules.housing.models import Decoration, HouseTier, PlayerHouse
from app.modules.inventory.models import (
    InventoryItem,
    ItemDefinition,
    PlayerFirstHarvest,
)
from app.modules.notifications.models import Notification
from app.modules.pets.models import PlayerPet
from app.modules.players.models import Player
from app.modules.profile.models import EncounterHint, Feedback, PlayerProfile
from app.modules.progression.models import (
    GoalDefinition,
    GoalProgress,
    LoginStreak,
    PlayerStatistic,
)
from app.modules.realtime.models import MessageRecipient, NearbyMessage, Presence
from app.modules.shop.models import (
    CollectionEntry,
    ItemRule,
    Purchase,
    Sale,
    StarterGrant,
)
from app.modules.social.community_models import (
    ChatReceipt,
    GiftWishlistAllocation,
    SocialPreferences,
    SocialRevision,
    WishlistEntry,
)
from app.modules.social.models import (
    DirectMessage,
    FarmInvitation,
    FarmVisitSession,
    Friendship,
    Gift,
    PlayerBlock,
    PlayerReport,
    Trade,
)
from app.modules.trees.models import CutTree, SpawnedTree
from app.modules.world.models import PlayerWorld, WorldState

__all__ = [
    # Declarative base
    "Base",
    # auth
    "AccountToken",
    "RefreshToken",
    # economy
    "EconomyTransaction",
    "PlayerEconomy",
    "PlayerExperience",
    "PlayerLevelReward",
    # events
    "EventClaim",
    "WorldEvent",
    # farming
    "FarmTile",
    # fishing
    "FishingSession",
    "FishingSpot",
    "GroundDrop",
    # housing
    "Decoration",
    "HouseTier",
    "PlayerHouse",
    # inventory
    "InventoryItem",
    "ItemDefinition",
    "PlayerFirstHarvest",
    # notifications
    "Notification",
    # pets
    "PlayerPet",
    # players
    "Player",
    # profile
    "EncounterHint",
    "Feedback",
    "PlayerProfile",
    # progression
    "GoalDefinition",
    "GoalProgress",
    "LoginStreak",
    "PlayerStatistic",
    #market 
    "PlayerShop",
    "ShopListing",
    "ShopSale",
    # realtime
    "MessageRecipient",
    "NearbyMessage",
    "Presence",
    # shop
    "CollectionEntry",
    "ItemRule",
    "Purchase",
    "Sale",
    "StarterGrant",
    # social
    "ChatReceipt",
    "DirectMessage",
    "FarmInvitation",
    "FarmVisitSession",
    "Friendship",
    "Gift",
    "GiftWishlistAllocation",
    "PlayerBlock",
    "PlayerReport",
    "SocialPreferences",
    "SocialRevision",
    "Trade",
    # trees
    "CutTree",
    "SpawnedTree",
    "WishlistEntry",
    # world
    "PlayerWorld",
    "WorldState",
]