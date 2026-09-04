"""Repeatable, idempotent demo catalog seed. Synthetic data only — no real
customers, prices, or inventory. Safe to run against any environment; it never
touches orders.
"""

from app.db import get_session_factory
from app.models import Product

CATALOG = [
    {
        "sku": "BDX-MUG-001",
        "name": "Bedoux Ceramic Mug",
        "description": "Matte-glazed 350ml mug with the Bedoux wordmark.",
        "category": "kitchen",
        "price_cents": 1400,
        "image_key": "products/mug-001.svg",
    },
    {
        "sku": "BDX-TOTE-001",
        "name": "Bedoux Canvas Tote",
        "description": "Heavyweight cotton canvas tote, natural finish.",
        "category": "bags",
        "price_cents": 2200,
        "image_key": "products/tote-001.svg",
    },
    {
        "sku": "BDX-TEE-001",
        "name": "Bedoux Logo Tee",
        "description": "Organic cotton crewneck, screen-printed logo.",
        "category": "apparel",
        "price_cents": 2800,
        "image_key": "products/tee-001.svg",
    },
    {
        "sku": "BDX-CAP-001",
        "name": "Bedoux Trucker Cap",
        "description": "Structured five-panel cap, embroidered front.",
        "category": "apparel",
        "price_cents": 2500,
        "image_key": "products/cap-001.svg",
    },
    {
        "sku": "BDX-STK-001",
        "name": "Bedoux Sticker Pack",
        "description": "Set of six vinyl die-cut stickers.",
        "category": "accessories",
        "price_cents": 900,
        "image_key": "products/sticker-001.svg",
    },
    {
        "sku": "BDX-BOTL-001",
        "name": "Bedoux Insulated Bottle",
        "description": "500ml double-wall stainless steel bottle.",
        "category": "kitchen",
        "price_cents": 3200,
        "image_key": "products/bottle-001.svg",
    },
]


def seed() -> int:
    """Insert any catalog rows missing by SKU. Returns the number inserted."""
    inserted = 0
    with get_session_factory()() as db:
        existing_skus = {sku for (sku,) in db.query(Product.sku).all()}
        for item in CATALOG:
            if item["sku"] in existing_skus:
                continue
            db.add(Product(**item))
            inserted += 1
        db.commit()
    return inserted


if __name__ == "__main__":
    count = seed()
    print(f"seeded {count} new product(s); {len(CATALOG)} total in catalog definition")
