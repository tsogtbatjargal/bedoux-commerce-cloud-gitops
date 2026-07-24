import type { HealthStatus, Order, OrderItemIn, Product } from "./types";

// Same-origin "/api" in the MVP deployment (Kubernetes Ingress routes /api to
// the API Service — see docs/architecture.md). Overridable for local dev
// against a directly-exposed API port.
const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "/api";

class ApiError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...init,
  });
  if (!response.ok) {
    const body = await response.text();
    throw new ApiError(response.status, body || response.statusText);
  }
  return response.json() as Promise<T>;
}

export interface ProductFilters {
  category?: string;
  q?: string;
}

export function listProducts(filters: ProductFilters = {}): Promise<Product[]> {
  const params = new URLSearchParams();
  if (filters.category) params.set("category", filters.category);
  if (filters.q) params.set("q", filters.q);
  const qs = params.toString();
  return request<Product[]>(`/products${qs ? `?${qs}` : ""}`);
}

export function getProduct(id: string): Promise<Product> {
  return request<Product>(`/products/${id}`);
}

export function createOrder(items: OrderItemIn[]): Promise<Order> {
  return request<Order>("/orders", {
    method: "POST",
    body: JSON.stringify({ items }),
  });
}

export function getOrder(id: string): Promise<Order> {
  return request<Order>(`/orders/${id}`);
}

export function getHealth(): Promise<HealthStatus> {
  return request<HealthStatus>("/health");
}

export { ApiError };
