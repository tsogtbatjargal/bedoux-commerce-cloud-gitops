from collections.abc import Generator
from functools import lru_cache

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.database_credentials import resolve_database_url


class Base(DeclarativeBase):
    pass


@lru_cache
def get_engine() -> Engine:
    """One Engine per process, built on first use rather than at import.

    resolve_database_url() makes a live Secrets Manager call in that mode, so an
    eager module-level engine meant importing this module -- including transitively,
    via app.models importing Base -- always paid for that call, even for callers
    that only wanted Base's metadata (Alembic's migrations/env.py, for one, already
    calls resolve_database_url() and builds its own engine; the eager engine here
    used to run before that with nothing consuming it).
    """
    return create_engine(resolve_database_url(), pool_pre_ping=True)


@lru_cache
def get_session_factory() -> sessionmaker[Session]:
    return sessionmaker(bind=get_engine(), autoflush=False, autocommit=False)


def get_db() -> Generator[Session, None, None]:
    db = get_session_factory()()
    try:
        yield db
    finally:
        db.close()
