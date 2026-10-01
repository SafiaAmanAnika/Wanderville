from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine, pool

from app.core.config import settings
from app.db.model_registry import Base

config = context.config
if config.config_file_name:
    fileConfig(config.config_file_name, disable_existing_loggers=False)
target_metadata = Base.metadata


def configure(connection=None):
    options = dict(
        target_metadata=target_metadata, compare_type=True, compare_server_default=True
    )
    if connection is None:
        context.configure(
            url=settings.database_url,
            literal_binds=True,
            dialect_opts={"paramstyle": "named"},
            **options,
        )
    else:
        context.configure(connection=connection, **options)
    with context.begin_transaction():
        context.run_migrations()


if context.is_offline_mode():
    configure()
elif config.attributes.get("connection") is not None:
    configure(config.attributes["connection"])
else:
    engine = create_engine(settings.database_url, poolclass=pool.NullPool)
    with engine.connect() as connection:
        configure(connection)
    engine.dispose()
