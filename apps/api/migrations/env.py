from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.database_credentials import resolve_database_url
from app.db import Base
from app import models  # noqa: F401  ensures models are registered on Base.metadata

config = context.config
database_url = resolve_database_url()
# ConfigParser's default interpolation treats a literal "%" specially (it expects
# "%%" or "%(name)s"); a URL-encoded password containing "%" (e.g. "+" -> "%2B")
# crashes set_main_option with "invalid interpolation syntax" before any connection
# is attempted. Escaping here round-trips correctly: BasicInterpolation un-escapes
# "%%" back to "%" whenever engine_from_config later reads the value.
config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
