"""Order pricing (M5). Pure — no database, no HTTP framework, no import-time I/O.

Prices always come from the catalog, never the client — the single rule this API's
security depends on most. Before this module, that rule lived inline in the FastAPI
route handler, interleaved with the SQLAlchemy query that resolved the catalog. Its
five tests all required a live Postgres connection to run, because there was no way
to exercise the rule without also exercising the query.

price_order() takes the parsed request and an already-resolved catalog (a plain
dict — the caller does the querying; this module never touches a Session). Two
adapters exist at that seam: a SQLAlchemy query result in production, a literal
dict in tests.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Protocol

from app.schemas import OrderCreate


class ProductNotFound(Exception):
    """One or more requested product ids are absent from the catalog."""

    def __init__(self, missing_ids: set[uuid.UUID]) -> None:
        self.missing_ids = missing_ids
        ids = ", ".join(str(product_id) for product_id in missing_ids)
        super().__init__(f"unknown product id(s): {ids}")


class CatalogProduct(Protocol):
    """Whatever the catalog lookup returns per product — only price_cents matters
    for pricing. A SQLAlchemy Product row satisfies this without any adapter."""

    price_cents: int


@dataclass(frozen=True)
class PricedLine:
    product_id: uuid.UUID
    quantity: int
    unit_price_cents: int

    @property
    def line_total_cents(self) -> int:
        return self.unit_price_cents * self.quantity


@dataclass(frozen=True)
class PricedOrder:
    lines: list[PricedLine]

    @property
    def total_cents(self) -> int:
        return sum(line.line_total_cents for line in self.lines)


def price_order(
    payload: OrderCreate, products_by_id: dict[uuid.UUID, CatalogProduct]
) -> PricedOrder:
    """Price every requested line from products_by_id. Raises ProductNotFound if
    any requested product_id is not a key in products_by_id.

    payload.items never carries a price — OrderItemIn has no such field — but this
    is where that guarantee is enforced even if one were ever added by mistake:
    only products_by_id[...].price_cents is read.
    """
    requested_ids = {item.product_id for item in payload.items}
    missing = requested_ids - products_by_id.keys()
    if missing:
        raise ProductNotFound(missing)

    lines = [
        PricedLine(
            product_id=item.product_id,
            quantity=item.quantity,
            unit_price_cents=products_by_id[item.product_id].price_cents,
        )
        for item in payload.items
    ]
    return PricedOrder(lines=lines)
