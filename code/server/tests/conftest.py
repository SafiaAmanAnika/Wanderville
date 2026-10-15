"""Tests never read DATABASE_URL or the developer's .env database connection.

SQLite uses a temporary file with foreign keys enabled. For PostgreSQL, explicitly
set WANDERVILLE_TEST_DATABASE_URL to a database whose name ends in _test and
WANDERVILLE_ALLOW_TEST_RESET=1. Only that named disposable DB may be rebuilt.
"""

import os
from pathlib import Path
from types import SimpleNamespace

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy.engine import make_url
from sqlalchemy.orm import sessionmaker

os.environ["WANDERVILLE_ENV"] = "test"
os.environ["DATABASE_URL"] = "sqlite://"
os.environ["JWT_SECRET_KEY"] = "test-only-secret-do-not-use-for-deployment"
os.environ["DEV_ALLOW_WORLD_MUTATION"] = "false"
os.environ["FARM_CONSUME_INVENTORY"] = "true"
os.environ["STARTING_AURA"] = "0"
os.environ["VOICE_ENABLED"] = "false"
os.environ["WORLD_WORKER_ENABLED"] = "false"
os.environ["VOICE_STUN_URLS"] = ""
os.environ["VOICE_TURN_URLS"] = ""
os.environ["VOICE_TURN_SECRET"] = ""

from app.core import progression  # noqa: E402
from app.core.config import settings  # noqa: E402
from app.core.rate_limit import limiter  # noqa: E402
from app.db.model_registry import Base  # noqa: E402
from app.db.seed import seed_reference_data  # noqa: E402
from app.db.session import get_db, make_engine  # noqa: E402
from app.main import app  # noqa: E402
from app.modules.auth import email  # noqa: E402


@pytest.fixture(scope="session")
def test_engine(tmp_path_factory):
    test_url = os.environ.get("WANDERVILLE_TEST_DATABASE_URL")
    if test_url:
        url = make_url(test_url)
        if (
            url.get_backend_name() != "postgresql"
            or not (url.database or "").endswith("_test")
            or os.environ.get("WANDERVILLE_ALLOW_TEST_RESET") != "1"
        ):
            pytest.fail(
                "PostgreSQL tests require a disposable *_test database and WANDERVILLE_ALLOW_TEST_RESET=1"
            )
    else:
        test_url = f"sqlite:///{tmp_path_factory.mktemp('database') / 'test.db'}"
    engine = make_engine(test_url)
    cfg = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    with engine.begin() as connection:
        cfg.attributes["connection"] = connection
        command.upgrade(cfg, "head")
    yield engine
    engine.dispose()


@pytest.fixture(autouse=True)
def clean_database(test_engine):
    with test_engine.begin() as connection:
        for table in reversed(Base.metadata.sorted_tables):
            connection.execute(table.delete())
    limiter.clear()
    # Pin every setting a test depends on. Settings load from .env, so without
    # this a developer's local file (for example one that disables verification
    # for private play) silently changes what the suite asserts.
    settings.wanderville_env = "test"
    settings.farm_consume_inventory = True
    settings.dev_allow_world_mutation = False
    settings.require_email_verification = True
    settings.world_worker_enabled = False
    factory = sessionmaker(test_engine, expire_on_commit=False, autoflush=False)
    with factory() as db:
        seed_reference_data(db)
    yield


@pytest.fixture
def session_factory(test_engine):
    return sessionmaker(test_engine, expire_on_commit=False, autoflush=False)


@pytest.fixture
def db(session_factory):
    with session_factory() as session:
        yield session


@pytest.fixture(autouse=True)
def mailbox(monkeypatch):
    messages = []
    monkeypatch.setattr(
        email, "send_account_email", lambda *args: messages.append(args)
    )
    return messages


@pytest.fixture
def client(session_factory):
    def override():
        with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client
    app.dependency_overrides.clear()


@pytest.fixture
def account(client, mailbox):
    def create(name="player_one", verify=True):
        payload = {
            "username": name,
            "email": f"{name}@example.com",
            "password": "Strong-Pass123!",
        }
        response = client.post("/auth/signup", json=payload)
        assert response.status_code == 200, response.text
        player = response.json()["data"]
        raw = mailbox[-1][2]
        if not verify:
            return SimpleNamespace(id=player["id"], payload=payload, verify_token=raw)
        assert (
            client.get("/auth/verify-email", params={"token": raw}).status_code == 200
        )
        response = client.post(
            "/auth/login", json={"username": name, "password": payload["password"]}
        )
        assert response.status_code == 200, response.text
        tokens = response.json()["data"]
        return SimpleNamespace(
            id=player["id"],
            payload=payload,
            tokens=tokens,
            headers={"Authorization": f"Bearer {tokens['access_token']}"},
        )

    return create


@pytest.fixture
def reach_level(client):
    """Advance a player to an exact level through the real XP endpoint."""

    def advance(user, level):
        floor = progression.level_info(level).min_xp
        current = client.get("/economy/xp", headers=user.headers).json()["data"]
        gap = floor - current["total_xp"]
        if gap > 0:
            response = client.post(
                "/economy/xp/gain",
                headers=user.headers,
                json={"xp_amount": gap, "source": "test"},
            )
            assert response.status_code == 200, response.text
        data = client.get("/economy/xp", headers=user.headers).json()["data"]
        assert data["level"] == level, data
        return data

    return advance
