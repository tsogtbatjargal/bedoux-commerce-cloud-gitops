export interface Product {
  id: string;
  sku: string;
  name: string;
  description: string;
  category: string;
  price_cents: number;
  image_path: string;
}

export interface OrderItemOut {
  product_id: string;
  name: string;
  quantity: number;
  unit_price_cents: number;
  line_total_cents: number;
}

export interface Order {
  id: string;
  status: string;
  total_cents: number;
  created_at: string;
  items: OrderItemOut[];
}

export interface OrderItemIn {
  product_id: string;
  quantity: number;
}

export interface HealthStatus {
  status: string;
  orders_enabled: boolean;
}
