import os

import pytest

DATABASE_URL = os.environ.get("BEDOUX_DATABASE_URL")

requires_db = pytest.mark.skipif(
    not DATABASE_URL, reason="BEDOUX_DATABASE_URL not set; skipping DB integration tests"
)


@pytest.fixture
def db_engine():
    # Builds its own Engine rather than app.db.get_engine(), which is @lru_cache'd
    # process-wide (M5) -- a test needing a different database per test, not just
    # per process, must bypass app.db the same way this fixture already does.
    from sqlalchemy import create_engine

    return create_engine(DATABASE_URL)


@pytest.fixture
def client(db_engine):
    """A TestClient wired to the real BEDOUX_DATABASE_URL, with each test's
    products/orders/order_items rows cleared before it runs so tests don't
    depend on each other's leftover data."""
    from sqlalchemy import text

    from app.main import app

    with db_engine.begin() as conn:
        conn.execute(text("TRUNCATE order_items, orders, products RESTART IDENTITY CASCADE"))

    from fastapi.testclient import TestClient

    with TestClient(app) as c:
        yield c
