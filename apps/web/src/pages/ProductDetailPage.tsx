import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { getProduct } from "../api/client";
import { useCart } from "../cart/CartContext";
import type { Product } from "../api/types";
import { formatCents } from "../format";

export function ProductDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { addItem } = useCart();
  const [product, setProduct] = useState<Product | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "not-found" | "error">("loading");
  const [added, setAdded] = useState(false);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    setStatus("loading");
    getProduct(id)
      .then((data) => {
        if (!cancelled) {
          setProduct(data);
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

  if (status === "loading") return <p>Loading product…</p>;
  if (status === "not-found") {
    return (
      <section>
        <p>We couldn't find that product.</p>
        <Link to="/">Back to catalog</Link>
      </section>
    );
  }
  if (status === "error" || !product) {
    return <p role="alert">Could not load this product. Try again shortly.</p>;
  }

  return (
    <section aria-label="Product detail">
      <Link to="/">← Back to catalog</Link>
      <h1>{product.name}</h1>
      <img src={product.image_path} alt="" width={240} height={240} />
      <p>{product.description}</p>
      <p>{formatCents(product.price_cents)}</p>
      <button
        type="button"
        onClick={() => {
          addItem(product, 1);
          setAdded(true);
        }}
      >
        Add to cart
      </button>
      {added && (
        <p role="status">
          Added to cart. <button type="button" onClick={() => navigate("/cart")}>View cart</button>
        </p>
      )}
    </section>
  );
}
