from pydantic import BaseModel

from app.modules.economy.schemas import EconomyResponse, XPResponse
from app.modules.farming.schemas import FarmGridResponse
from app.modules.inventory.schemas import InventoryListResponse
from app.modules.world.schemas import WorldStateResponse


class StateBundleResponse(BaseModel):
    """Everything a client needs after one round trip.

    The Godot client previously fetched these six sections sequentially after
    every farm action, so one interaction cost seven round trips. Every section
    here is byte-identical to its standalone endpoint, so existing clients and
    the individual routes keep working unchanged.
    """

    profile: dict
    farm: FarmGridResponse
    world: WorldStateResponse
    inventory: InventoryListResponse
    economy: EconomyResponse
    experience: XPResponse
    # Resolved session: authenticatedPlayer / ownedWorld / currentWorld / mode /
    # host. The client uses it to decide whether to show owner or visitor
    # controls; the server never trusts it for authorization.
    session: dict