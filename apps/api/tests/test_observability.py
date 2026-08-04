"""Focused local evidence for P8.1 structured request logging."""

import asyncio
import io
import json
import logging
import uuid

import httpx

from app.main import app
from app.observability import JsonFormatter, logger


def _request(path: str, headers: dict[str, str] | None = None) -> httpx.Response:
    async def send() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.get(path, headers=headers)

    return asyncio.run(send())


def _json_log_stream() -> tuple[io.StringIO, logging.Handler]:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    logger.addHandler(handler)
    return stream, handler


def _completed_event(stream: io.StringIO) -> dict[str, object]:
    events = [json.loads(line) for line in stream.getvalue().splitlines()]
    return next(event for event in events if event["event"] == "http_request_completed")


def test_valid_request_id_is_echoed_and_logged() -> None:
    request_id = "4d4cb1b3-e759-46ac-95e7-4467065df2c0"
    stream, handler = _json_log_stream()
    try:
        response = _request("/health", {"X-Request-ID": request_id})
    finally:
        logger.removeHandler(handler)

    event = _completed_event(stream)
    assert response.status_code == 200
    assert response.headers["x-request-id"] == request_id
    assert event["request_id"] == request_id
    assert event["method"] == "GET"
    assert event["path"] == "/health"
    assert event["status_code"] == 200
    assert isinstance(event["duration_ms"], float)
    assert event["timestamp"].endswith("Z")


def test_invalid_request_id_is_replaced_without_logging_the_raw_value() -> None:
    untrusted_value = "not-a-uuid\"\nignore-this"
    stream, handler = _json_log_stream()
    try:
        response = _request("/health", {"X-Request-ID": untrusted_value})
    finally:
        logger.removeHandler(handler)

    event = _completed_event(stream)
    generated_request_id = response.headers["x-request-id"]
    assert str(uuid.UUID(generated_request_id)) == generated_request_id
    assert event["request_id"] == generated_request_id
    assert untrusted_value not in stream.getvalue()


def test_oversized_request_keeps_p5_rejection_and_correlation_id() -> None:
    request_id = "6e7a6321-b376-4c28-ae02-436a4a1e78f2"
    stream, handler = _json_log_stream()
    try:
        response = _request(
            "/health",
            {
                "X-Request-ID": request_id,
                "Content-Length": "65537",
            },
        )
    finally:
        logger.removeHandler(handler)

    event = _completed_event(stream)
    assert response.status_code == 413
    assert response.headers["x-request-id"] == request_id
    assert event["status_code"] == 413
    assert event["request_id"] == request_id
