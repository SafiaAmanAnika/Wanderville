from pathlib import Path

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import inspect

from app.db.model_registry import Base
from app.db.session import make_engine


def test_migrated_schema_matches_models(test_engine):
    with test_engine.connect() as connection:
        context = MigrationContext.configure(
            connection, opts={"compare_type": True, "compare_server_default": True}
        )
        assert compare_metadata(context, Base.metadata) == []


def test_baseline_round_trip_on_fresh_database(tmp_path):
    engine = make_engine(f"sqlite:///{tmp_path / 'migration.db'}")
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
