import { Link, Outlet } from "react-router-dom";
import { useCart } from "../cart/CartContext";

export function Layout() {
  const { totalItems } = useCart();

  return (
    <div>
      <header>
        <nav aria-label="Main">
          <Link to="/">Bedoux</Link>
          <Link to="/cart">Cart ({totalItems})</Link>
        </nav>
      </header>
      <main>
        <Outlet />
      </main>
      <footer>
        <p>Bedoux Commerce — build 0.2</p>
      </footer>
    </div>
  );
}
