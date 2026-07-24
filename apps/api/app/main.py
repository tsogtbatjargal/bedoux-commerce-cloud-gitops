from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.config import settings
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
async def limit_request_body_size(request: Request, call_next):
    """Request-bounds half of the P5 kill-switch decision — a Content-Length
    over the cap is rejected before it reaches a handler. Trusts the header
    rather than draining the body, which is enough for a demo endpoint with no
    chunked-upload use case."""
    content_length = request.headers.get("content-length")
    if content_length is not None and int(content_length) > settings.max_request_body_bytes:
        return JSONResponse(status_code=413, content={"detail": "request body too large"})
    return await call_next(request)


app.include_router(products.router)
app.include_router(orders.router)


@app.get("/health")
def health() -> dict[str, object]:
    """Liveness/readiness probe target. Must never touch the database. Also
    reports orders_enabled so the frontend can render a deliberate "ordering
    disabled" state instead of surfacing raw 503s from /orders."""
    return {"status": "ok", "orders_enabled": settings.orders_enabled}
