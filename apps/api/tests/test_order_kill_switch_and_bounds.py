"""Unit tests for the P5 order-write kill switch and request bounds
(docs/IMPLEMENTATION-PLAN.md pending decision #4). No real database needed —
SQLAlchemy's engine connects lazily, and the kill-switch check in
app.routers.orders.create_order runs before any query, same as the
body-size-limit middleware runs before routing.
"""

from fastapi.testclient import TestClient

from app import config
from app.main import app

client = TestClient(app)


def test_orders_disabled_returns_503_not_a_crash(monkeypatch):
    monkeypatch.setattr(config.settings, "orders_enabled", False)
    response = client.post("/orders", json={"items": [{"product_id": str("0" * 8 + "-0000-0000-0000-000000000000"), "quantity": 1}]})
    assert response.status_code == 503
    assert response.json()["detail"] == "ordering is currently disabled"


def test_health_reports_orders_enabled_state(monkeypatch):
    monkeypatch.setattr(config.settings, "orders_enabled", False)
    response = client.get("/health")
    assert response.json() == {"status": "ok", "orders_enabled": False}


def test_order_rejects_more_than_twenty_lines():
    items = [{"product_id": f"{i:08d}-0000-0000-0000-000000000000", "quantity": 1} for i in range(21)]
    response = client.post("/orders", json={"items": items})
    assert response.status_code == 422


def test_request_over_body_size_limit_rejected():
    oversized = "x" * (config.settings.max_request_body_bytes + 1)
    response = client.post(
        "/orders",
        content=oversized,
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 413
    assert response.json() == {"detail": "request body too large"}
