from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier

import pytest
from sqlalchemy import select

from app.core.clock import utcnow
from app.core.exceptions import AppError
from app.modules.auth.service import AuthService
from app.modules.economy.schemas import TransactionRequest
from app.modules.economy.service import EconomyService
from app.modules.farming.schemas import PlantRequest
from app.modules.farming.service import FarmingService
from app.modules.inventory.models import InventoryItem
from app.modules.inventory.schemas import ItemRequest, TransferRequest
from app.modules.inventory.service import InventoryService

pytestmark = pytest.mark.postgres


@pytest.fixture(autouse=True)
def requires_postgres(test_engine):
    if test_engine.dialect.name != "postgresql":
        pytest.skip(
            "Set WANDERVILLE_TEST_DATABASE_URL and WANDERVILLE_ALLOW_TEST_RESET=1 to run real PostgreSQL concurrency tests"
        )


def concurrent(factory, action):
    barrier = Barrier(2)

    def run(index):
        with factory() as db:
            barrier.wait(timeout=10)
            try:
                action(db, index)
                return "ok"
            except AppError as error:
                return error.code

    with ThreadPoolExecutor(max_workers=2) as pool:
        return list(pool.map(run, (0, 1)))


def test_no_double_spend(account, session_factory, db):
    user = account()
    # The first successful login already grants 10 Aura.
    result = concurrent(
        session_factory,
        lambda session, _: EconomyService(session).change(
            user.id, TransactionRequest(amount=10), earn=False
        ),
    )
    assert sorted(result) == ["INSUFFICIENT_FUNDS", "ok"]
    db.expire_all()
    assert EconomyService(db).get(user.id).aura_balance == 0


def test_starter_claim_is_once_under_concurrency(account, session_factory, db):
    from app.modules.shop.service import ShopService, STARTER_ITEMS

    user = account()
    assert concurrent(session_factory, lambda session, _: ShopService(session).claim_starter(user.id)) == ['ok', 'ok']
    db.expire_all()
    rows = InventoryService(db).repo.list(user.id)
    assert {r.item_code: r.quantity for r in rows} == STARTER_ITEMS


def test_replayed_sale_is_once_under_concurrency(account, session_factory, db):
    from app.modules.shop.service import ShopService
    from app.modules.shop.schemas import SaleRequest

    user = account()
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code='wheat', quantity=3))
    request = SaleRequest(item_code='wheat', quantity=2, request_id='concurrent_sale')
    assert concurrent(session_factory, lambda session, _: ShopService(session).sell(user.id, request)) == ['ok', 'ok']
    db.expire_all()
    assert InventoryService(db).repo.stack(user.id, 'wheat').quantity == 1
    assert EconomyService(db).get(user.id).aura_balance == 34


def test_no_double_harvest(account, session_factory, db):
    user = account()
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code="wheat"))
    now = utcnow()
    service = FarmingService(db)
    tile = service.plant(user.id, PlantRequest(x=1, y=2, item_code="wheat"), now).plot
    service.water(user.id, tile.id, now)
    now += timedelta(seconds=18)
    result = concurrent(
        session_factory,
        lambda session, _: FarmingService(session).harvest(user.id, tile.id, now),
    )
    assert sorted(result) == ["FARM_EMPTY", "ok"]
    db.expire_all()
    assert (
        db.scalar(
            select(InventoryItem).where(InventoryItem.player_id == user.id)
        ).quantity
        == 1
    )


def test_refresh_token_has_one_successor(account, session_factory):
    user = account()
    result = concurrent(
        session_factory,
        lambda session, _: AuthService(session).refresh(user.tokens["refresh_token"]),
    )
    assert sorted(result) == ["REVOKED_REFRESH_TOKEN", "ok"]


def test_reciprocal_transfer_does_not_deadlock(account, session_factory, db):
    first, second = account(), account("second")
    for user in (first, second):
        InventoryService(db).add_compatibility(
            user.id, ItemRequest(item_code="wheat", quantity=2)
        )

    def action(session, index):
        sender, receiver = (first, second) if index == 0 else (second, first)
        InventoryService(session).transfer(
            sender.id,
            TransferRequest(
                item_code="wheat",
                quantity=1,
                to_player_username=receiver.payload["username"],
            ),
        )

    assert concurrent(session_factory, action) == ["ok", "ok"]
    db.expire_all()
    for user in (first, second):
        assert InventoryService(db).list(user.id).total_quantity == 2


def test_duplicate_planting_consumes_one_seed(account, session_factory, db):
    user = account()
    InventoryService(db).add_compatibility(
        user.id, ItemRequest(item_code="wheat", quantity=2)
    )
    request = PlantRequest(x=1, y=2, item_code="wheat")
    result = concurrent(
        session_factory,
        lambda session, _: FarmingService(session).plant(user.id, request),
    )
    assert sorted(result) == ["FARM_PLOT_OCCUPIED", "ok"]
    db.expire_all()
    assert InventoryService(db).list(user.id).total_quantity == 1
    assert EconomyService(db).xp(user.id).total_xp == 1


def test_first_bonus_is_once_for_simultaneous_same_species_harvests(account, session_factory, db):
    from app.modules.inventory.models import PlayerFirstHarvest

    user = account()
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code="wheat_seed", quantity=2))
    now = utcnow()
    farm = FarmingService(db)
    plots = [farm.plant(user.id, PlantRequest(x=index + 1, y=2, item_code="wheat_seed"), now).plot for index in range(2)]
    for plot in plots:
        farm.water(user.id, plot.id, now)
    result = concurrent(session_factory, lambda session, index: FarmingService(session).harvest(
        user.id, plots[index].id, now + timedelta(seconds=18)))
    assert result == ["ok", "ok"]
    db.expire_all()
    assert InventoryService(db).repo.stack(user.id, "wheat").quantity == 2
    assert EconomyService(db).xp(user.id).total_xp == 2 + 5 + 5 + 15
    assert len(list(db.scalars(select(PlayerFirstHarvest)))) == 1


def test_simultaneous_level_crossing_pays_aura_once(account, session_factory, db):
    from app.modules.economy.models import PlayerLevelReward
    from app.modules.economy.schemas import XPGainRequest

    user = account()
    EconomyService(db).gain_compatibility(user.id, XPGainRequest(xp_amount=79))
    result = concurrent(session_factory, lambda session, _: EconomyService(session).gain_compatibility(
        user.id, XPGainRequest(xp_amount=1)))
    assert result == ["ok", "ok"]
    db.expire_all()
    assert EconomyService(db).xp(user.id).total_xp == 81
    assert EconomyService(db).get(user.id).aura_balance == 35
    assert len(list(db.scalars(select(PlayerLevelReward)))) == 1


def test_simultaneous_purchase_is_idempotent(account, session_factory, db):
    from app.modules.shop.service import ShopService
    from app.modules.shop.schemas import PurchaseRequest

    user = account()
    request = PurchaseRequest(
        request_id="parallel_purchase", item_code="wheat_seed", quantity=1
    )
    results = concurrent(
        session_factory, lambda session, _: ShopService(session).buy(user.id, request)
    )
    assert results == ["ok", "ok"]
    db.expire_all()
    assert InventoryService(db).repo.stack(user.id, "wheat_seed").quantity == 1
    assert EconomyService(db).get(user.id).aura_balance == 4


def test_simultaneous_gift_claim_has_one_winner(account, session_factory, db):
    from app.modules.social.service import SocialService
    from app.modules.social.schemas import GiftRequest

    a, b = account(), account("gift_receiver")
    service = SocialService(db)
    service.request(a.id, b.id)
    service.respond(b.id, a.id, "accept")
    InventoryService(db).add_compatibility(
        a.id, ItemRequest(item_code="wheat", quantity=1)
    )
    gift = service.gift(
        a.id,
        GiftRequest(
            target_id=b.id, item_code="wheat", quantity=1, request_id="parallel_gift"
        ),
    )
    results = concurrent(
        session_factory,
        lambda session, _: SocialService(session).claim_gift(b.id, gift["id"]),
    )
    assert sorted(results) == ["ALREADY_CLAIMED", "ok"]
    db.expire_all()
    assert InventoryService(db).repo.stack(b.id, "wheat").quantity == 1


def test_simultaneous_trade_acceptance_has_one_winner(account, session_factory, db):
    from app.modules.social.service import SocialService
    from app.modules.social.schemas import TradeRequest

    a, b = account(), account("trade_receiver")
    service = SocialService(db)
    service.request(a.id, b.id)
    service.respond(b.id, a.id, "accept")
    for user, code in ((a, "wheat"), (b, "sugarcane")):
        InventoryService(db).add_compatibility(user.id, ItemRequest(item_code=code))
    trade = service.propose(a.id, TradeRequest(
        target_id=b.id, request_id="parallel_trade", offered_code="wheat",
        offered_quantity=1, wanted_code="sugarcane", wanted_quantity=1,
    ))
    results = concurrent(session_factory, lambda session, _: SocialService(session).trade_action(
        b.id, trade["id"], "accept",
    ))
    assert sorted(results) == ["TRADE_CLOSED", "ok"]
    db.expire_all()
    inventory = InventoryService(db)
    assert inventory.repo.stack(a.id, "wheat") is None
    assert inventory.repo.stack(b.id, "sugarcane") is None
    assert inventory.repo.stack(a.id, "sugarcane").quantity == 1
    assert inventory.repo.stack(b.id, "wheat").quantity == 1


def test_wishlist_final_quantity_has_only_one_donor(account, session_factory, db):
    from app.modules.social.service import SocialService
    from app.modules.social.schemas import GiftRequest
    from app.modules.social.community import CommunityService
    from app.modules.social.community_schemas import WishlistRequest
    from app.modules.social.models import Gift
    owner, a, b = account("wish_race_owner"), account("wish_race_a"), account("wish_race_b")
    for donor in (a, b):
        SocialService(db).request(owner.id, donor.id)
        SocialService(db).respond(donor.id, owner.id, "accept")
        InventoryService(db).add_compatibility(donor.id, ItemRequest(item_code="wheat", quantity=1))
    entry = CommunityService(db).put(owner.id, "wheat", WishlistRequest(quantity=1))
    result = concurrent(session_factory, lambda session, i: SocialService(session).gift((a, b)[i].id,
        GiftRequest(target_id=owner.id, request_id=f"wishlist_race_{i}", item_code="wheat", quantity=1,
                    wishlist_entry_id=entry["id"], wishlist_version=entry["version"])))
    assert sorted(result) == ["WISHLIST_CHANGED", "ok"]
    db.expire_all()
    gifts = list(db.scalars(select(Gift).where(Gift.receiver_id == owner.id)))
    assert len(gifts) == 1
    state = CommunityService(db).wishlist(owner.id, owner.id)[0]
    assert state["pending_quantity"] == 1 and state["remaining_quantity"] == 0
