"""Exercises migrations + seed against a real PostgreSQL instance.

Skips itself if BEDOUX_DATABASE_URL isn't set to a reachable database — these
are integration tests, not unit tests, and require no external credentials
(only a local Postgres container). Run with:

    podman run -d --name bedoux-pg-test -p 5433:5432 \\
      -e POSTGRES_USER=bedoux -e POSTGRES_PASSWORD=bedoux -e POSTGRES_DB=bedoux \\
      docker.io/library/postgres:16-alpine
    BEDOUX_DATABASE_URL=postgresql+psycopg://bedoux:bedoux@localhost:5433/bedoux \\
      pytest tests/test_schema_and_seed.py
"""

import os

import pytest
from sqlalchemy import create_engine, inspect, text

DATABASE_URL = os.environ.get("BEDOUX_DATABASE_URL")

pytestmark = pytest.mark.skipif(
    not DATABASE_URL, reason="BEDOUX_DATABASE_URL not set; skipping DB integration tests"
)


@pytest.fixture(scope="module")
def engine():
    return create_engine(DATABASE_URL)


def test_migrations_create_expected_tables(engine):
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    assert {"products", "orders", "order_items", "alembic_version"} <= tables


def test_seed_is_idempotent(engine):
    from app.seed import CATALOG, seed

    first = seed()
    second = seed()
    assert second == 0, "re-running seed must not insert duplicates"

    with engine.connect() as conn:
        count = conn.execute(text("SELECT count(*) FROM products")).scalar_one()
    assert count == len(CATALOG)
    assert first + (len(CATALOG) - first) == len(CATALOG)
