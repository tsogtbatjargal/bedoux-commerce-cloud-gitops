import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { App } from "./App";
import { CartProvider } from "./cart/CartContext";
import type { Product, Order } from "./api/types";

const mug: Product = {
  id: "11111111-1111-1111-1111-111111111111",
  sku: "BDX-MUG-001",
  name: "Bedoux Ceramic Mug",
  description: "A mug.",
  category: "kitchen",
  price_cents: 1400,
  image_url: "/static/products/mug-001.svg",
};

function jsonResponse(body: unknown, status = 200) {
  return Promise.resolve(
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  );
}

function renderApp(initialPath = "/") {
  return render(
    <CartProvider>
      <MemoryRouter initialEntries={[initialPath]}>
        <App />
      </MemoryRouter>
    </CartProvider>,
  );
}

describe("catalog to order confirmation, driven through rendered DOM only", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("browses the catalog, views a product, adds to cart, and submits an order", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.startsWith("/api/products/") && url.includes(mug.id)) {
        return jsonResponse(mug);
      }
      if (url.startsWith("/api/products")) {
        return jsonResponse([mug]);
      }
      if (url.startsWith("/api/orders") && url === "/api/orders") {
        return jsonResponse(
          {
            id: "order-123",
            status: "submitted",
            total_cents: 2800,
            created_at: "2026-07-18T00:00:00Z",
            items: [
              {
                product_id: mug.id,
                name: mug.name,
                quantity: 2,
                unit_price_cents: 1400,
                line_total_cents: 2800,
              },
            ],
          } satisfies Order,
        );
      }
      if (url === "/api/orders/order-123") {
        return jsonResponse({
          id: "order-123",
          status: "submitted",
          total_cents: 2800,
          created_at: "2026-07-18T00:00:00Z",
          items: [
            {
              product_id: mug.id,
              name: mug.name,
              quantity: 2,
              unit_price_cents: 1400,
              line_total_cents: 2800,
            },
          ],
        } satisfies Order);
      }
      throw new Error(`unexpected fetch: ${url}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderApp("/");

    // Catalog loads and shows the mug.
    await waitFor(() => expect(screen.getByText("Bedoux Ceramic Mug")).toBeInTheDocument());

    // Navigate to the product detail page.
    await user.click(screen.getByText("Bedoux Ceramic Mug"));
    await waitFor(() => expect(screen.getByRole("heading", { name: "Bedoux Ceramic Mug" })).toBeInTheDocument());

    // Add to cart twice to reach quantity 2 (exercises the merge-not-duplicate path).
    await user.click(screen.getByRole("button", { name: "Add to cart" }));
    await user.click(screen.getByRole("button", { name: "Add to cart" }));

    // Go to the cart and submit the order.
    await user.click(screen.getByRole("link", { name: /Cart \(2\)/ }));
    await waitFor(() => expect(screen.getByText("Your cart")).toBeInTheDocument());
    expect(screen.getByText("$28.00")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Submit order" }));

    // Lands on the confirmation page with the real order data.
    await waitFor(() =>
      expect(screen.getByText("Thank you — your order is confirmed")).toBeInTheDocument(),
    );
    expect(screen.getByText(/order-123/)).toBeInTheDocument();
    expect(screen.getByText(/Bedoux Ceramic Mug × 2/)).toBeInTheDocument();

    // The cart was cleared after a successful submission.
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/orders",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ items: [{ product_id: mug.id, quantity: 2 }] }),
      }),
    );
  });

  it("shows an alert if the catalog fails to load", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.resolve(new Response("boom", { status: 500 }))),
    );

    renderApp("/");

    await waitFor(() => expect(screen.getByRole("alert")).toBeInTheDocument());
  });
});
