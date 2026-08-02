import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.image_storage import ImageUrlResolver, get_image_url_resolver
from app.models import Product
from app.schemas import ProductOut

router = APIRouter(prefix="/products", tags=["products"])


def _product_out(product: Product, image_urls: ImageUrlResolver) -> ProductOut:
    return ProductOut(
        id=product.id,
        sku=product.sku,
        name=product.name,
        description=product.description,
        category=product.category,
        price_cents=product.price_cents,
        image_url=image_urls.url_for(product.image_key),
    )


@router.get("", response_model=list[ProductOut])
def list_products(
    category: str | None = None,
    q: str | None = None,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
    image_urls: ImageUrlResolver = Depends(get_image_url_resolver),
) -> list[ProductOut]:
    limit = max(1, min(limit, 100))
    offset = max(0, offset)

    stmt = select(Product)
    if category:
        stmt = stmt.where(Product.category == category)
    if q:
        stmt = stmt.where(Product.name.ilike(f"%{q}%"))
    stmt = stmt.order_by(Product.name).offset(offset).limit(limit)

    return [_product_out(product, image_urls) for product in db.scalars(stmt)]


@router.get("/{product_id}", response_model=ProductOut)
def get_product(
    product_id: uuid.UUID,
    db: Session = Depends(get_db),
    image_urls: ImageUrlResolver = Depends(get_image_url_resolver),
) -> ProductOut:
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="product not found")
    return _product_out(product, image_urls)
