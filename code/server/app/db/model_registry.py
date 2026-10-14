"""Explicit metadata discovery; no FastAPI or route imports."""

from app.db.base import Base
from app.modules.auth.models import AccountToken, RefreshToken
from app.modules.economy.models import (
    EconomyTransaction,
    PlayerEconomy,
    PlayerExperience,
    PlayerLevelReward,
)
from app.modules.farming.models import FarmTile
from app.modules.inventory.models import (
    InventoryItem,
    ItemDefinition,
    PlayerFirstHarvest,
)
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
    "PlayerLevelReward",
    "FarmTile",
    "InventoryItem",
    "ItemDefinition",
    "PlayerFirstHarvest",
    "PlayerWorld",
    "WorldState",
]

from app.modules.notifications.models import Notification  # noqa: F401, E402

from app.modules.profile.models import PlayerProfile, EncounterHint, Feedback  # noqa: F401, E402

from app.modules.housing.models import HouseTier, PlayerHouse, Decoration  # noqa: F401, E402

from app.modules.pets.models import PlayerPet  # noqa: F401, E402

from app.modules.shop.models import ItemRule, CollectionEntry, Purchase, Sale, StarterGrant  # noqa: F401, E402

from app.modules.progression.models import (  # noqa: F401, E402
    GoalDefinition,
    GoalProgress,
    PlayerStatistic,
    LoginStreak,
)  # noqa: F401, E402

from app.modules.fishing.models import FishingSpot, FishingSession, GroundDrop  # noqa: F401, E402

from app.modules.social.models import (  # noqa: F401, E402
    Friendship,
    PlayerBlock,
    Gift,
    Trade,
    FarmInvitation,
    FarmVisitSession,
    DirectMessage,
    PlayerReport,
)  # noqa: F401, E402

from app.modules.events.models import WorldEvent, EventClaim  # noqa: F401, E402

from app.modules.realtime.models import Presence, NearbyMessage, MessageRecipient  # noqa: F401, E402
from app.modules.social.community_models import SocialPreferences, WishlistEntry, GiftWishlistAllocation, ChatReceipt, SocialRevision  # noqa: F401, E402
