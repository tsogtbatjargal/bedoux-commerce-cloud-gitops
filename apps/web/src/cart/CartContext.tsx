import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type { Product } from "../api/types";

export interface CartLine {
  product: Product;
  quantity: number;
}

interface CartContextValue {
  lines: CartLine[];
  addItem: (product: Product, quantity?: number) => void;
  removeItem: (productId: string) => void;
  setQuantity: (productId: string, quantity: number) => void;
  clear: () => void;
  totalCents: number;
  totalItems: number;
}

const CartContext = createContext<CartContextValue | undefined>(undefined);

const STORAGE_KEY = "bedoux-cart-v1";

function loadInitialLines(): CartLine[] {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as CartLine[]) : [];
  } catch {
    // Corrupt or unavailable storage — start with an empty cart rather than
    // crashing the page.
    return [];
  }
}

export function CartProvider({ children }: { children: ReactNode }) {
  const [lines, setLines] = useState<CartLine[]>(loadInitialLines);

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(lines));
  }, [lines]);

  const addItem = useCallback((product: Product, quantity = 1) => {
    setLines((prev) => {
      const existing = prev.find((line) => line.product.id === product.id);
      if (existing) {
        return prev.map((line) =>
          line.product.id === product.id
            ? { ...line, quantity: line.quantity + quantity }
            : line,
        );
      }
      return [...prev, { product, quantity }];
    });
  }, []);

  const removeItem = useCallback((productId: string) => {
    setLines((prev) => prev.filter((line) => line.product.id !== productId));
  }, []);

  const setQuantity = useCallback((productId: string, quantity: number) => {
    setLines((prev) => {
      if (quantity <= 0) {
        return prev.filter((line) => line.product.id !== productId);
      }
      return prev.map((line) =>
        line.product.id === productId ? { ...line, quantity } : line,
      );
    });
  }, []);

  const clear = useCallback(() => setLines([]), []);

  const totalCents = useMemo(
    () => lines.reduce((sum, line) => sum + line.product.price_cents * line.quantity, 0),
    [lines],
  );
  const totalItems = useMemo(
    () => lines.reduce((sum, line) => sum + line.quantity, 0),
    [lines],
  );

  const value = useMemo(
    () => ({ lines, addItem, removeItem, setQuantity, clear, totalCents, totalItems }),
    [lines, addItem, removeItem, setQuantity, clear, totalCents, totalItems],
  );

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useCart(): CartContextValue {
  const ctx = useContext(CartContext);
  if (!ctx) {
    throw new Error("useCart must be used within a CartProvider");
  }
  return ctx;
}
