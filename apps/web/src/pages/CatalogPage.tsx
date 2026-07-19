import { useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { listProducts } from "../api/client";
import type { Product } from "../api/types";
import { formatCents } from "../format";

export function CatalogPage() {
  const [products, setProducts] = useState<Product[]>([]);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  const [searchParams, setSearchParams] = useSearchParams();

  const category = searchParams.get("category") ?? "";
  const q = searchParams.get("q") ?? "";

  useEffect(() => {
    let cancelled = false;
    setStatus("loading");
    listProducts({ category: category || undefined, q: q || undefined })
      .then((data) => {
        if (!cancelled) {
          setProducts(data);
          setStatus("ready");
        }
      })
      .catch(() => {
        if (!cancelled) setStatus("error");
      });
    return () => {
      cancelled = true;
    };
  }, [category, q]);

  const categories = useMemo(
    () => Array.from(new Set(products.map((p) => p.category))).sort(),
    [products],
  );

  return (
    <section aria-label="Product catalog">
      <h1>Catalog</h1>

      <form
        role="search"
        onSubmit={(e) => {
          e.preventDefault();
          const form = new FormData(e.currentTarget);
          const next: Record<string, string> = {};
          const searchValue = form.get("q");
          if (typeof searchValue === "string" && searchValue) next.q = searchValue;
          if (category) next.category = category;
          setSearchParams(next);
        }}
      >
        <label htmlFor="q">Search</label>
        <input id="q" name="q" defaultValue={q} placeholder="Search products" />
        <button type="submit">Search</button>
      </form>

      {categories.length > 0 && (
        <div aria-label="Filter by category">
          <button
            type="button"
            aria-pressed={category === ""}
            onClick={() => setSearchParams(q ? { q } : {})}
          >
            All
          </button>
          {categories.map((c) => (
            <button
              key={c}
              type="button"
              aria-pressed={category === c}
              onClick={() => setSearchParams(q ? { q, category: c } : { category: c })}
            >
              {c}
            </button>
          ))}
        </div>
      )}

      {status === "loading" && <p>Loading products…</p>}
      {status === "error" && <p role="alert">Could not load the catalog. Try again shortly.</p>}
      {status === "ready" && products.length === 0 && <p>No products match your search.</p>}

      <ul>
        {products.map((product) => (
          <li key={product.id}>
            <Link to={`/products/${product.id}`}>
              <img src={product.image_path} alt="" width={80} height={80} />
              <span>{product.name}</span>
              <span>{formatCents(product.price_cents)}</span>
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
