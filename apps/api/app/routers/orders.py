import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.models import Order, OrderItem, Product
from app.pricing import ProductNotFound, price_order
from app.schemas import OrderCreate, OrderItemOut, OrderOut

router = APIRouter(prefix="/orders", tags=["orders"])


def _to_order_out(order: Order, products_by_id: dict[uuid.UUID, Product]) -> OrderOut:
    return OrderOut(
        id=order.id,
        status=order.status,
        total_cents=order.total_cents,
        created_at=order.created_at,
        items=[
            OrderItemOut(
                product_id=item.product_id,
                name=products_by_id[item.product_id].name,
                quantity=item.quantity,
                unit_price_cents=item.unit_price_cents,
                line_total_cents=item.unit_price_cents * item.quantity,
            )
            for item in order.items
        ],
    )


@router.post("", response_model=OrderOut, status_code=201)
def create_order(payload: OrderCreate, db: Session = Depends(get_db)) -> OrderOut:
    # Kill switch (pending decision #4, docs/IMPLEMENTATION-PLAN.md): off by
    # default in the AWS session profile so the public ALB demo can't be used to
    # write real-looking orders outside the actual demonstration window. A clear
    # 503 here — not a raw crash — is what lets the frontend show a deliberate
    # "ordering disabled" state instead of looking broken.
    if not settings.orders_enabled:
        raise HTTPException(status_code=503, detail="ordering is currently disabled")

    product_ids = {item.product_id for item in payload.items}
    products = db.query(Product).filter(Product.id.in_(product_ids)).all()
    products_by_id = {p.id: p for p in products}

    try:
        priced = price_order(payload, products_by_id)
    except ProductNotFound as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    order_items = [
        OrderItem(
            product_id=line.product_id,
            quantity=line.quantity,
            unit_price_cents=line.unit_price_cents,
        )
        for line in priced.lines
    ]

    order = Order(status="submitted", total_cents=priced.total_cents, items=order_items)
    db.add(order)
    db.commit()
    db.refresh(order)

    return _to_order_out(order, products_by_id)


@router.get("/{order_id}", response_model=OrderOut)
def get_order(order_id: uuid.UUID, db: Session = Depends(get_db)) -> OrderOut:
    order = db.get(Order, order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="order not found")

    product_ids = {item.product_id for item in order.items}
    products = db.query(Product).filter(Product.id.in_(product_ids)).all()
    products_by_id = {p.id: p for p in products}

    return _to_order_out(order, products_by_id)
