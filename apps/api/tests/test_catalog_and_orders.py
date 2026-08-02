"""Integration tests for the catalog and order endpoints. Require a real
PostgreSQL database — see tests/test_schema_and_seed.py for how to start one.
Skip automatically when BEDOUX_DATABASE_URL is unset (see conftest.requires_db).
"""

from tests.conftest import requires_db


@requires_db
def test_catalog_happy_path_and_order_confirmation(client, db_engine):
    from app.seed import CATALOG, seed

    inserted = seed()
    assert inserted == len(CATALOG)

    # Browse the catalog.
    listed = client.get("/products")
    assert listed.status_code == 200
    products = listed.json()
    assert len(products) == len(CATALOG)
    assert all(product["image_url"].startswith("/static/products/") for product in products)
    assert all("image_path" not in product for product in products)

    # Filter by category.
    kitchen = client.get("/products", params={"category": "kitchen"})
    assert kitchen.status_code == 200
    assert all(p["category"] == "kitchen" for p in kitchen.json())
    assert len(kitchen.json()) == 2  # mug + bottle, per app/seed.py

    # Search by name.
    mug_search = client.get("/products", params={"q": "mug"})
    assert mug_search.status_code == 200
    assert len(mug_search.json()) == 1
    assert "Mug" in mug_search.json()[0]["name"]

    # View product detail.
    mug = mug_search.json()[0]
    detail = client.get(f"/products/{mug['id']}")
    assert detail.status_code == 200
    assert detail.json()["sku"] == mug["sku"]

    # Add two different products to a cart and submit the order.
    tote = next(p for p in products if p["sku"] == "BDX-TOTE-001")
    expected_total = mug["price_cents"] * 2 + tote["price_cents"] * 1

    create_resp = client.post(
        "/orders",
        json={
            "items": [
                {"product_id": mug["id"], "quantity": 2},
                {"product_id": tote["id"], "quantity": 1},
            ]
        },
    )
    assert create_resp.status_code == 201
    order = create_resp.json()
    assert order["status"] == "submitted"
    assert order["total_cents"] == expected_total
    assert len(order["items"]) == 2

    # View order confirmation by id — a separate request, as a customer
    # revisiting the confirmation page would do.
    confirmation = client.get(f"/orders/{order['id']}")
    assert confirmation.status_code == 200
    assert confirmation.json() == order


@requires_db
def test_order_rejects_unknown_product(client):
    resp = client.post(
        "/orders",
        json={"items": [{"product_id": "00000000-0000-0000-0000-000000000000", "quantity": 1}]},
    )
    assert resp.status_code == 400


@requires_db
def test_order_price_cannot_be_tampered_by_client(client):
    from app.seed import seed

    seed()
    products = client.get("/products").json()
    mug = next(p for p in products if p["sku"] == "BDX-MUG-001")

    # The schema has no price field on OrderItemIn — even if a client sends
    # one, it's silently dropped by validation, never trusted.
    resp = client.post(
        "/orders",
        json={
            "items": [
                {"product_id": mug["id"], "quantity": 1, "unit_price_cents": 1}
            ]
        },
    )
    assert resp.status_code == 201
    order = resp.json()
    assert order["items"][0]["unit_price_cents"] == mug["price_cents"]
    assert order["items"][0]["unit_price_cents"] != 1


@requires_db
def test_get_missing_order_returns_404(client):
    resp = client.get("/orders/00000000-0000-0000-0000-000000000000")
    assert resp.status_code == 404


@requires_db
def test_get_missing_product_returns_404(client):
    resp = client.get("/products/00000000-0000-0000-0000-000000000000")
    assert resp.status_code == 404
