import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ProductOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    sku: str
    name: str
    description: str
    category: str
    price_cents: int
    image_path: str


class OrderItemIn(BaseModel):
    product_id: uuid.UUID
    quantity: int = Field(gt=0, le=100)


class OrderCreate(BaseModel):
    items: list[OrderItemIn] = Field(min_length=1)


class OrderItemOut(BaseModel):
    product_id: uuid.UUID
    name: str
    quantity: int
    unit_price_cents: int
    line_total_cents: int


class OrderOut(BaseModel):
    id: uuid.UUID
    status: str
    total_cents: int
    created_at: datetime
    items: list[OrderItemOut]
