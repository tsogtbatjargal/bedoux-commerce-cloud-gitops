import { Route, Routes } from "react-router-dom";
import { Layout } from "./components/Layout";
import { CatalogPage } from "./pages/CatalogPage";
import { ProductDetailPage } from "./pages/ProductDetailPage";
import { CartPage } from "./pages/CartPage";
import { OrderConfirmationPage } from "./pages/OrderConfirmationPage";

export function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<CatalogPage />} />
        <Route path="products/:id" element={<ProductDetailPage />} />
        <Route path="cart" element={<CartPage />} />
        <Route path="orders/:id" element={<OrderConfirmationPage />} />
      </Route>
    </Routes>
  );
}
