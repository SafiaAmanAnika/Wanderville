from app.core.clock import utcnow
from app.modules.economy.service import EconomyService
from app.modules.farming.service import FarmingService
from app.modules.inventory.service import InventoryService
from app.modules.profile.service import ProfileService
from app.modules.state.schemas import StateBundleResponse
from app.modules.world.service import WorldService


def build_bundle(db, player_id) -> StateBundleResponse:
    """Compose the six gameplay sections from one session and one clock read.

    Each service call here is the same read its standalone route performs. The
    shared session is what removes the latency: six sequential HTTP round trips
    collapse into one request, and growth is evaluated against a single `now`
    so the farm and the world clock cannot disagree within a response.
    """
    world_service = WorldService(db)
    # One timestamp for the whole response; farm growth and world environment
    # are otherwise sampled microseconds apart and can straddle a boundary.
    now = utcnow()
    farming = FarmingService(db)
    return StateBundleResponse(
        profile=ProfileService(db).get(player_id),
        farm=farming.list(player_id, now=now),
        world=world_service.state(now=now),
        inventory=InventoryService(db).list(player_id),
        economy=EconomyService(db).get(player_id),
        experience=EconomyService(db).xp(player_id),
    )