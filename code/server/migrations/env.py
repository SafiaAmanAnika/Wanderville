from logging.config import fileConfig

from alembic import context
from sqlalchemy import Boolean, DefaultClause, Table, create_engine, event, false, pool, true

from app.core.config import settings
from app.db.model_registry import Base

config = context.config
if config.config_file_name:
    fileConfig(config.config_file_name, disable_existing_loggers=False)
target_metadata = Base.metadata


def portable_boolean_defaults(table, connection, **kwargs):
    """Render historical SQLite Boolean literals portably without rewriting revisions."""
    if connection.dialect.name != "postgresql":
        return
    for column in table.columns:
        default = column.server_default
        if isinstance(column.type, Boolean) and default is not None:
            literal = str(default.arg).strip()
            if literal in {"0", "1"}:
                column.server_default = DefaultClause(true() if literal == "1" else false())


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
    event.listen(Table, "before_create", portable_boolean_defaults)
    try:
        with context.begin_transaction():
            context.run_migrations()
    finally:
        event.remove(Table, "before_create", portable_boolean_defaults)


if context.is_offline_mode():
    configure()
elif config.attributes.get("connection") is not None:
    configure(config.attributes["connection"])
else:
    engine = create_engine(settings.database_url, poolclass=pool.NullPool)
    with engine.connect() as connection:
        configure(connection)
    engine.dispose()
