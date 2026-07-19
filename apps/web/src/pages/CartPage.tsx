import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { createOrder } from "../api/client";
import { useCart } from "../cart/CartContext";
import { formatCents } from "../format";

export function CartPage() {
  const { lines, removeItem, setQuantity, clear, totalCents } = useCart();
  const navigate = useNavigate();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (lines.length === 0) {
    return (
      <section aria-label="Cart">
        <h1>Your cart is empty</h1>
        <Link to="/">Browse the catalog</Link>
      </section>
    );
  }

  async function submitOrder() {
    setSubmitting(true);
    setError(null);
    try {
      const order = await createOrder(
        lines.map((line) => ({ product_id: line.product.id, quantity: line.quantity })),
      );
      clear();
      navigate(`/orders/${order.id}`);
    } catch {
      setError("Could not submit your order. Please try again.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section aria-label="Cart">
      <h1>Your cart</h1>
      <ul>
        {lines.map((line) => (
          <li key={line.product.id}>
            <span>{line.product.name}</span>
            <label>
              Quantity
              <input
                type="number"
                min={1}
                max={100}
                value={line.quantity}
                onChange={(e) => setQuantity(line.product.id, Number(e.target.value))}
              />
            </label>
            <span>{formatCents(line.product.price_cents * line.quantity)}</span>
            <button type="button" onClick={() => removeItem(line.product.id)}>
              Remove
            </button>
          </li>
        ))}
      </ul>
      <p>Total: {formatCents(totalCents)}</p>
      {error && <p role="alert">{error}</p>}
      <button type="button" onClick={submitOrder} disabled={submitting}>
        {submitting ? "Submitting…" : "Submit order"}
      </button>
    </section>
  );
}
