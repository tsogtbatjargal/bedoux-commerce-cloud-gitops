"""Unit tests for app.pricing (M5). No database — products_by_id is a plain dict,
so these run in milliseconds and never skip for lack of BEDOUX_DATABASE_URL.

The database-backed integration tests in tests/test_catalog_and_orders.py still
exercise the same rules end-to-end through real HTTP requests and a real query;
these are additional, not a replacement.
"""

import uuid

import pytest

from app.pricing import PricedOrder, ProductNotFound, price_order
from app.schemas import OrderCreate, OrderItemIn


class FakeProduct:
    """The only thing price_order needs from a catalog row is price_cents."""

    def __init__(self, price_cents: int) -> None:
        self.price_cents = price_cents


def _order_create(*items: tuple[uuid.UUID, int]) -> OrderCreate:
    return OrderCreate(
        items=[OrderItemIn(product_id=product_id, quantity=quantity) for product_id, quantity in items]
    )


def test_single_line_prices_from_catalog_not_client() -> None:
    mug_id = uuid.uuid4()
    payload = _order_create((mug_id, 2))
    products_by_id = {mug_id: FakeProduct(price_cents=1400)}

    priced = price_order(payload, products_by_id)

    assert len(priced.lines) == 1
    line = priced.lines[0]
    assert line.product_id == mug_id
    assert line.quantity == 2
    assert line.unit_price_cents == 1400
    assert line.line_total_cents == 2800


def test_total_cents_sums_every_line() -> None:
    mug_id, tote_id = uuid.uuid4(), uuid.uuid4()
    payload = _order_create((mug_id, 2), (tote_id, 1))
    products_by_id = {
        mug_id: FakeProduct(price_cents=1400),
        tote_id: FakeProduct(price_cents=2200),
    }

    priced = price_order(payload, products_by_id)

    assert priced.total_cents == 1400 * 2 + 2200 * 1


def test_unknown_product_id_raises_product_not_found() -> None:
    known_id, unknown_id = uuid.uuid4(), uuid.uuid4()
    payload = _order_create((known_id, 1), (unknown_id, 1))
    products_by_id = {known_id: FakeProduct(price_cents=900)}

    with pytest.raises(ProductNotFound) as excinfo:
        price_order(payload, products_by_id)

    assert excinfo.value.missing_ids == {unknown_id}
    assert str(unknown_id) in str(excinfo.value)


def test_multiple_unknown_product_ids_are_all_reported() -> None:
    unknown_a, unknown_b = uuid.uuid4(), uuid.uuid4()
    payload = _order_create((unknown_a, 1), (unknown_b, 1))

    with pytest.raises(ProductNotFound) as excinfo:
        price_order(payload, products_by_id={})

    assert excinfo.value.missing_ids == {unknown_a, unknown_b}


def test_a_price_that_only_exists_on_the_request_is_never_read() -> None:
    """price_order only ever reads products_by_id[...].price_cents. OrderItemIn has
    no price field at all -- this proves the pricing rule holds even against an
    object that has an extra, unrelated price-shaped attribute sitting on it,
    guarding against a future refactor accidentally reading the wrong source."""

    product_id = uuid.uuid4()
    payload = _order_create((product_id, 3))

    class ProductWithATrap(FakeProduct):
        # If price_order ever reads anything but products_by_id[id].price_cents,
        # this is the number that would leak through instead.
        unit_price_cents = 1  # attacker-shaped attribute name, deliberately unused

    products_by_id = {product_id: ProductWithATrap(price_cents=5000)}

    priced = price_order(payload, products_by_id)

    assert priced.lines[0].unit_price_cents == 5000


def test_priced_order_and_priced_line_are_immutable() -> None:
    product_id = uuid.uuid4()
    payload = _order_create((product_id, 1))
    priced = price_order(payload, {product_id: FakeProduct(price_cents=100)})

    with pytest.raises((AttributeError, TypeError)):
        priced.lines[0].unit_price_cents = 1  # type: ignore[misc]
    with pytest.raises((AttributeError, TypeError)):
        priced.lines = []  # type: ignore[misc]


def test_empty_catalog_with_no_requested_items_is_unreachable_via_schema() -> None:
    """OrderCreate itself enforces min_length=1 on items, so price_order is never
    called with zero lines in production -- documented here rather than tested
    as a price_order behaviour, since OrderCreate(items=[]) fails validation
    before price_order would ever see it."""

    with pytest.raises(Exception):  # noqa: B017 - pydantic's own ValidationError
        OrderCreate(items=[])
