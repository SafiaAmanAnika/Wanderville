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
    EconomyService(db).change(user.id, TransactionRequest(amount=10), earn=True)
    result = concurrent(
        session_factory,
        lambda session, _: EconomyService(session).change(
            user.id, TransactionRequest(amount=10), earn=False
        ),
    )
    assert sorted(result) == ["INSUFFICIENT_FUNDS", "ok"]
    db.expire_all()
    assert EconomyService(db).get(user.id).aura_balance == 0


def test_no_double_harvest(account, session_factory, db):
    user = account()
    InventoryService(db).add_compatibility(user.id, ItemRequest(item_code="wheat"))
    now = utcnow()
    service = FarmingService(db)
    tile = service.plant(user.id, PlantRequest(x=1, y=2, item_code="wheat"), now).plot
    for _ in range(3):
        service.water(user.id, tile.id, now)
        now += timedelta(seconds=60)
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
