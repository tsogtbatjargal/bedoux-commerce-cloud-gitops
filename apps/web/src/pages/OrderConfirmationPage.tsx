import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { getOrder } from "../api/client";
import type { Order } from "../api/types";
import { formatCents } from "../format";

export function OrderConfirmationPage() {
  const { id } = useParams<{ id: string }>();
  const [order, setOrder] = useState<Order | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "not-found" | "error">("loading");

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    getOrder(id)
      .then((data) => {
        if (!cancelled) {
          setOrder(data);
          setStatus("ready");
        }
      })
      .catch((err) => {
        if (cancelled) return;
        setStatus(err?.status === 404 ? "not-found" : "error");
      });
    return () => {
      cancelled = true;
    };
  }, [id]);

  if (status === "loading") return <p>Loading your order…</p>;
  if (status === "not-found") {
    return (
      <section>
        <p>We couldn't find that order.</p>
        <Link to="/">Back to catalog</Link>
      </section>
    );
  }
  if (status === "error" || !order) {
    return <p role="alert">Could not load your order confirmation.</p>;
  }

  return (
    <section aria-label="Order confirmation">
      <h1>Thank you — your order is confirmed</h1>
      <p>
        Order <strong>{order.id}</strong> — status: {order.status}
      </p>
      <ul>
        {order.items.map((item) => (
          <li key={item.product_id}>
            {item.name} × {item.quantity} — {formatCents(item.line_total_cents)}
          </li>
        ))}
      </ul>
      <p>Total: {formatCents(order.total_cents)}</p>
      <Link to="/">Continue shopping</Link>
    </section>
  );
}
