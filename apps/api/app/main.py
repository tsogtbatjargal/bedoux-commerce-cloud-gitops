from time import perf_counter

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.config import settings
from app.observability import logger, request_id_from_header, reset_request_id, set_request_id
from app.routers import orders, products

app = FastAPI(
    title="Bedoux Commerce Cloud API",
    description=(
        "Products and orders API for the Bedoux Commerce Cloud reference "
        "implementation. See docs/IMPLEMENTATION-PLAN.md for scope."
    ),
    version="0.1.0",
)


@app.middleware("http")
async def observe_request(request: Request, call_next):
    """Attach a correlation ID, preserve the P5 request cap, and emit one safe JSON event."""

    request_id = request_id_from_header(request.headers.get("x-request-id"))
    request.state.request_id = request_id
    token = set_request_id(request_id)
    started = perf_counter()
    status_code = 500

    try:
        # Request-bounds half of the P5 kill-switch decision. Trusts Content-Length rather
        # than draining the body, which is enough for a demo endpoint with no chunked uploads.
        content_length = request.headers.get("content-length")
        if content_length is not None and int(content_length) > settings.max_request_body_bytes:
            response = JSONResponse(
                status_code=413, content={"detail": "request body too large"}
            )
        else:
            response = await call_next(request)

        status_code = response.status_code
        response.headers["X-Request-ID"] = request_id
        return response
    except Exception:
        logger.error(
            "request failed",
            extra={
                "event": "http_request_failed",
                "method": request.method,
                "path": request.url.path,
                "status_code": status_code,
            },
        )
        raise
    finally:
        logger.info(
            "request completed",
            extra={
                "event": "http_request_completed",
                "method": request.method,
                "path": request.url.path,
                "status_code": status_code,
                "duration_ms": round((perf_counter() - started) * 1000, 3),
            },
        )
        reset_request_id(token)


app.include_router(products.router)
app.include_router(orders.router)


@app.get("/health")
def health() -> dict[str, object]:
    """Liveness/readiness probe target. Must never touch the database. Also
    reports orders_enabled so the frontend can render a deliberate "ordering
    disabled" state instead of surfacing raw 503s from /orders."""
    return {"status": "ok", "orders_enabled": settings.orders_enabled}
