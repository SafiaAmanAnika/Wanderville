from datetime import timedelta

import pytest
from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError

from app.core.clock import utcnow
from app.db.model_registry import Base
from app.db.seed import seed_reference_data
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


def rejected(db, operation):
    with pytest.raises(IntegrityError), db.begin_nested():
        operation()
        db.flush()


@pytest.mark.parametrize("field", ["username", "email"])
def test_unique_accounts(account, db, field):
    user = account()
    values = dict(
        username="another", email="another@example.com", display_name="Another"
    )
    values[field] = user.payload[field]
    rejected(db, lambda: db.add(Player(**values)))


@pytest.mark.parametrize("quantity", [0, -1])
def test_positive_inventory_constraint(account, db, quantity):
    user = account()
    rejected(
        db,
        lambda: db.add(
            InventoryItem(player_id=user.id, item_code="wheat", quantity=quantity)
        ),
    )


def test_inventory_fk_and_unique_stack(account, db):
    user = account()
    rejected(
        db,
        lambda: db.add(
            InventoryItem(player_id=user.id, item_code="missing", quantity=1)
        ),
    )
    db.add(InventoryItem(player_id=user.id, item_code="wheat", quantity=1))
    db.commit()
    rejected(
        db,
        lambda: db.add(InventoryItem(player_id=user.id, item_code="wheat", quantity=2)),
    )


@pytest.mark.parametrize("column", ["aura_balance", "total_earned", "total_spent"])
def test_economy_nonnegative(account, db, column):
    user = account()
    rejected(
        db,
        lambda: db.execute(
            update(PlayerEconomy)
            .where(PlayerEconomy.player_id == user.id)
            .values(**{column: -1})
        ),
    )


@pytest.mark.parametrize("column,value", [("total_xp", -1), ("level", 0)])
def test_experience_constraints(account, db, column, value):
    user = account()
    rejected(
        db,
        lambda: db.execute(
            update(PlayerExperience)
            .where(PlayerExperience.player_id == user.id)
            .values(**{column: value})
        ),
    )


def test_world_tile_and_token_constraints(account, db):
    user = account()
    world = db.scalar(select(PlayerWorld).where(PlayerWorld.owner_id == user.id))
    rejected(db, lambda: db.add(PlayerWorld(owner_id=user.id)))
    db.add(FarmTile(world_id=world.id, x=1, y=1))
    db.commit()
    rejected(db, lambda: db.add(FarmTile(world_id=world.id, x=1, y=1)))
    rejected(
        db,
        lambda: db.add(
            FarmTile(
                world_id=world.id,
                x=2,
                y=1,
                crop_item_code="missing",
                planted_at=utcnow(),
                last_growth_update_at=utcnow(),
            )
        ),
    )
    token = db.scalar(select(RefreshToken))
    rejected(
        db,
        lambda: db.add(
            RefreshToken(
                player_id=user.id,
                token_hash=token.token_hash,
                expires_at=utcnow() + timedelta(days=1),
            )
        ),
    )
    token = db.scalar(select(AccountToken))
    rejected(
        db,
        lambda: db.add(
            AccountToken(
                player_id=user.id,
                token_hash=token.token_hash,
                token_type="password_reset",
                expires_at=utcnow() + timedelta(days=1),
            )
        ),
    )
    rejected(db, lambda: db.add(WorldState(id=2)))
    rejected(
        db,
        lambda: db.add(
            EconomyTransaction(
                player_id=user.id, amount=0, transaction_type="earn", reason="invalid"
            )
        ),
    )


def test_player_delete_cascades_private_data_only(account, db):
    user = account()
    world = db.scalar(select(PlayerWorld).where(PlayerWorld.owner_id == user.id))
    db.add_all(
        [
            FarmTile(world_id=world.id, x=1, y=1),
            InventoryItem(player_id=user.id, item_code="wheat", quantity=1),
            EconomyTransaction(
                player_id=user.id, amount=1, transaction_type="earn", reason="test"
            ),
        ]
    )
    db.commit()
    db.execute(delete(Player).where(Player.id == user.id))
    db.commit()
    for model in [
        PlayerWorld,
        PlayerEconomy,
        PlayerExperience,
        RefreshToken,
        AccountToken,
        InventoryItem,
        FarmTile,
        EconomyTransaction,
    ]:
        assert db.scalar(select(model)) is None, model.__tablename__
    assert len(db.scalars(select(ItemDefinition)).all()) == 75
    assert db.get(WorldState, 1) is not None


def test_world_delete_cascades_tiles(account, db):
    user = account()
    world = db.scalar(select(PlayerWorld).where(PlayerWorld.owner_id == user.id))
    db.add(FarmTile(world_id=world.id, x=2, y=3))
    db.commit()
    db.delete(world)
    db.commit()
    assert db.scalar(select(FarmTile)) is None
    assert db.get(Player, user.id) is not None


def test_seeds_are_idempotent_and_preserve_clock(db):
    state = db.get(WorldState, 1)
    original = (state.season_started_at, state.day_cycle_anchor_at, state.current_season,
                state.weather, state.season_duration_minutes, state.day_night_cycle_minutes)
    counts = {table.name: db.scalar(select(func.count()).select_from(table))
              for table in Base.metadata.sorted_tables}
    seed_reference_data(db)
    seed_reference_data(db)
    assert len(db.scalars(select(ItemDefinition)).all()) == 75
    assert (state.season_started_at, state.day_cycle_anchor_at, state.current_season,
            state.weather, state.season_duration_minutes, state.day_night_cycle_minutes) == original
    assert {table.name: db.scalar(select(func.count()).select_from(table))
            for table in Base.metadata.sorted_tables} == counts
    assert len(Base.metadata.tables) == 56


@pytest.mark.parametrize(
    "field,value",
    [
        ("max_stack", 0),
        ("sell_value", -1),
        ("buy_value", -1),
        ("growth_time_seconds", 0),
        ("xp_reward", -1),
    ],
)
def test_item_catalog_constraints(db, field, value):
    rejected(
        db,
        lambda: db.execute(
            update(ItemDefinition)
            .where(ItemDefinition.item_code == "wheat")
            .values(**{field: value})
        ),
    )
