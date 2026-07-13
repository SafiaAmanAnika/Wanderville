import os
from pathlib import Path
import sys

import pytest

TEST_DB_PATH = Path(__file__).with_name("test_world_service.db")
if TEST_DB_PATH.exists():
    TEST_DB_PATH.unlink()
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB_PATH.as_posix()}"
os.environ["JWT_SECRET_KEY"] = "test-secret-key"
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "60"
os.environ["DISABLE_RATE_LIMIT"] = "1"

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import Base, SessionLocal, engine  # noqa: E402
import app.models.player  # noqa: F401, E402
import app.models.refresh_token  # noqa: F401, E402
import app.models.world  # noqa: F401, E402
from app.models.player import Player  # noqa: E402
from app.models.world import World  # noqa: E402
from app.services import world_service  # noqa: E402
from app.services.auth_service import signup as auth_signup, hash_password  # noqa: E402


Base.metadata.create_all(bind=engine)


@pytest.fixture(autouse=True)
def clean_db():
    db = SessionLocal()
    try:
        db.query(World).delete()
        db.query(Player).delete()
        db.commit()
    finally:
        db.close()
    yield


@pytest.fixture
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def player(db):
    return auth_signup(
        db,
        username="svcplayer",
        email="svcplayer@test.com",
        password="Secret123!",
        display_name="Service Test",
    )


@pytest.fixture
def player_no_world(db):
    p = Player(
        username="svcplayer_noworld",
        hashed_password=hash_password("Secret123!"),
        display_name="No World",
        is_active=True,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def test_create_world(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id)
    assert world.owner_id == player.id
    assert world.name == "My World"
    assert world.tiles == {}
    assert world.id is not None


def test_create_world_custom_name(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id, name="Custom Land")
    assert world.name == "Custom Land"


def test_get_world_by_owner_returns_none_when_missing(db, player_no_world):
    assert world_service.get_world_by_owner(db, player_no_world.id) is None


def test_get_world_by_owner_returns_world(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id)
    found = world_service.get_world_by_owner(db, player.id)
    assert found is not None
    assert found.id == world.id


def test_update_tiles(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id)
    new_tiles = {"0,0": "grass", "1,0": "dirt"}
    updated = world_service.update_tiles(db, world.id, new_tiles)
    assert updated.tiles == new_tiles


def test_update_tiles_replaces_all(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id)
    world_service.update_tiles(db, world.id, {"0,0": "grass", "1,1": "dirt"})
    updated = world_service.update_tiles(db, world.id, {"5,5": "stone"})
    assert updated.tiles == {"5,5": "stone"}


def test_update_tiles_raises_for_missing_world(db):
    with pytest.raises(ValueError, match="not found"):
        world_service.update_tiles(db, 99999, {"0,0": "grass"})


def test_update_single_tile(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id)
    updated = world_service.update_single_tile(db, world.id, x=2, y=3, tile_type="water")
    assert updated.tiles["2,3"] == "water"


def test_update_single_tile_overwrites(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id)
    world_service.update_single_tile(db, world.id, x=0, y=0, tile_type="grass")
    updated = world_service.update_single_tile(db, world.id, x=0, y=0, tile_type="sand")
    assert updated.tiles["0,0"] == "sand"


def test_update_single_tile_preserves_others(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id)
    world_service.update_tiles(db, world.id, {"0,0": "grass", "1,1": "dirt"})
    updated = world_service.update_single_tile(db, world.id, x=5, y=5, tile_type="stone")
    assert updated.tiles["0,0"] == "grass"
    assert updated.tiles["1,1"] == "dirt"
    assert updated.tiles["5,5"] == "stone"


def test_update_single_tile_raises_for_missing_world(db):
    with pytest.raises(ValueError, match="not found"):
        world_service.update_single_tile(db, 99999, x=0, y=0, tile_type="grass")


def test_update_single_tile_negative_coords(db, player):
    db.query(World).filter(World.owner_id == player.id).delete()
    db.commit()
    world = world_service.create_world(db, player.id)
    updated = world_service.update_single_tile(db, world.id, x=-3, y=-7, tile_type="ice")
    assert updated.tiles["-3,-7"] == "ice"
