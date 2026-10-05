from pathlib import Path

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
import pytest
from sqlalchemy import inspect, text
from uuid import uuid4

from app.db.model_registry import Base
from app.db.session import make_engine


def test_migrated_schema_matches_models(test_engine):
    with test_engine.connect() as connection:
        context = MigrationContext.configure(
            connection, opts={"compare_type": True, "compare_server_default": True}
        )
        assert compare_metadata(context, Base.metadata) == []


@pytest.fixture
def migration_engine(test_engine, tmp_path):
    if test_engine.dialect.name == "sqlite":
        engine = make_engine(f"sqlite:///{tmp_path / 'migration.db'}")
        yield engine
        engine.dispose()
        return
    schema = "migration_" + uuid4().hex
    with test_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    engine = make_engine(test_engine.url.render_as_string(hide_password=False),
                         connect_args={"options": f"-csearch_path={schema}"})
    try:
        yield engine
    finally:
        engine.dispose()
        with test_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))


def test_baseline_round_trip_on_fresh_database(migration_engine):
    engine = migration_engine
    cfg = Config(str(Path(__file__).resolve().parents[2] / "alembic.ini"))
    with engine.begin() as connection:
        cfg.attributes["connection"] = connection
        command.upgrade(cfg, "head")
        assert set(inspect(connection).get_table_names()) == set(
            Base.metadata.tables
        ) | {"alembic_version"}
        command.check(cfg)
        command.downgrade(cfg, "base")
        assert inspect(connection).get_table_names() == ["alembic_version"]
        command.upgrade(cfg, "head")
        command.check(cfg)
    engine.dispose()


def test_upgrade_backfills_existing_accounts_without_losing_inventory(migration_engine):
    engine = migration_engine
    cfg = Config(str(Path(__file__).resolve().parents[2] / "alembic.ini"))
    with engine.begin() as connection:
        cfg.attributes["connection"] = connection
        command.upgrade(cfg, "0001_initial_schema")
        connection.execute(
            text(
                "INSERT INTO players (id, username, display_name) VALUES (7, 'existing', 'Existing')"
            )
        )
        connection.execute(
            text(
                "INSERT INTO item_definitions (item_code,name,category) VALUES ('old_item','Old Item','tool')"
            )
        )
        connection.execute(
            text(
                "INSERT INTO inventory_items (player_id,item_code,quantity) VALUES (7,'old_item',9)"
            )
        )
        connection.execute(text("INSERT INTO player_economy (player_id,aura_balance,total_earned) VALUES (7,123,123)"))
        connection.execute(text("INSERT INTO player_experience (player_id,total_xp,level) VALUES (7,50,1)"))
        connection.execute(text("INSERT INTO player_worlds (id,owner_id,name) VALUES (9,7,'Existing farm')"))
        connection.execute(text("INSERT INTO farm_tiles (world_id,x,y,crop_item_code,planted_at,last_growth_update_at) VALUES (9,2,3,'old_item',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)"))
        preserved = {}
        for table in ("players", "player_economy", "player_experience", "item_definitions", "inventory_items", "player_worlds", "farm_tiles"):
            # Later migrations add columns; only the pre-upgrade columns must
            # survive with identical values.
            columns = [c["name"] for c in inspect(connection).get_columns(table)]
            preserved[table] = (columns, connection.execute(text(f"SELECT {','.join(columns)} FROM {table}")).all())
        command.upgrade(cfg, "head")
        for table, (columns, rows) in preserved.items():
            assert connection.execute(text(f"SELECT {','.join(columns)} FROM {table}")).all() == rows
        command.check(cfg)
        assert (
            connection.scalar(
                text("SELECT quantity FROM inventory_items WHERE player_id=7")
            )
            == 9
        )
        assert (
            connection.scalar(
                text("SELECT water_charges FROM player_profiles WHERE player_id=7")
            )
            == 20
        )
        assert (
            connection.scalar(text("SELECT tier FROM player_houses WHERE player_id=7"))
            == 1
        )
        assert connection.scalar(text("SELECT count(*) FROM player_pets")) == 0
    engine.dispose()


def test_worker_cli_bootstraps_models_in_a_fresh_process(tmp_path):
    import os
    import subprocess
    import sys

    root = Path(__file__).resolve().parents[2]
    env = {
        **os.environ,
        "DATABASE_URL": f"sqlite:///{tmp_path / 'worker.db'}",
        "WANDERVILLE_ENV": "test",
    }
    for arguments in [
        ("alembic", "upgrade", "head"),
        ("app.db.seed",),
        ("app.modules.world.worker", "--once"),
    ]:
        result = subprocess.run(
            [sys.executable, "-m", *arguments],
            cwd=root,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr


def test_progression_migration_preserves_legacy_capacity_and_marks_historical_rewards(migration_engine):
    cfg = Config(str(Path(__file__).resolve().parents[2] / "alembic.ini"))
    with migration_engine.begin() as connection:
        cfg.attributes["connection"] = connection
        command.upgrade(cfg, "0005_shop_receipts")
        for player_id, xp, old_level in ((1, 250, 2), (2, 3000, 7), (3, 0, 1)):
            connection.execute(text("INSERT INTO players (id,username,display_name) VALUES (:id,:name,:name)"),
                               {"id": player_id, "name": f"old_{player_id}"})
            connection.execute(text("INSERT INTO player_economy (player_id,aura_balance) VALUES (:id,123)"), {"id": player_id})
            connection.execute(text("INSERT INTO player_experience (player_id,total_xp,level) VALUES (:id,:xp,:level)"),
                               {"id": player_id, "xp": xp, "level": old_level})
        command.upgrade(cfg, "head")
        assert connection.execute(text("SELECT player_id,total_xp,level,inventory_base_capacity FROM player_experience ORDER BY player_id")).all() == [
            (1, 250, 3, 180), (2, 3000, 10, 180), (3, 0, 1, 180)]
        assert connection.execute(text("SELECT player_id,level,aura FROM player_level_rewards ORDER BY player_id,level")).all() == [
            (1, 2, 0), (2, 2, 0), (2, 10, 0)]
        assert connection.execute(text("SELECT aura_balance FROM player_economy")).scalars().all() == [123, 123, 123]
        assert connection.scalar(text("SELECT count(*) FROM economy_transactions")) == 0
        command.upgrade(cfg, "head")
        assert connection.scalar(text("SELECT count(*) FROM player_level_rewards")) == 3
        command.check(cfg)
