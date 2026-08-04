"""Small, dependency-free observability boundary for the API.

Application request events are emitted as one JSON object per line so a container
runtime can forward them unchanged to the later P8.2 CloudWatch integration. The
schema deliberately excludes request bodies, query strings, headers, credentials,
and database URLs.
"""

from __future__ import annotations

import contextvars
import json
import logging
import sys
import uuid
from datetime import UTC, datetime

_request_id: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "request_id", default=None
)
_logger_name = "bedoux.api"
_handler_marker = "_bedoux_json_handler"


class JsonFormatter(logging.Formatter):
    """Render only the approved application log schema as a JSON object."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": datetime.fromtimestamp(record.created, UTC)
            .isoformat()
            .replace("+00:00", "Z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        request_id = getattr(record, "request_id", _request_id.get())
        if request_id is not None:
            payload["request_id"] = request_id

        for field in ("event", "method", "path", "status_code", "duration_ms"):
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value

        return json.dumps(payload, separators=(",", ":"), sort_keys=True)


def configure_logging() -> logging.Logger:
    """Configure the API logger once without changing unrelated library loggers."""

    logger = logging.getLogger(_logger_name)
    logger.setLevel(logging.INFO)
    logger.propagate = False

    if not any(getattr(handler, _handler_marker, False) for handler in logger.handlers):
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
        setattr(handler, _handler_marker, True)
        logger.addHandler(handler)

    return logger


logger = configure_logging()


def request_id_from_header(value: str | None) -> str:
    """Accept only canonical UUID correlation IDs; generate one for every other request."""

    if value is not None:
        try:
            return str(uuid.UUID(value))
        except ValueError:
            pass
    return str(uuid.uuid4())


def set_request_id(request_id: str) -> contextvars.Token[str | None]:
    """Set the request context for logs emitted while an HTTP request is handled."""

    return _request_id.set(request_id)


def reset_request_id(token: contextvars.Token[str | None]) -> None:
    _request_id.reset(token)
