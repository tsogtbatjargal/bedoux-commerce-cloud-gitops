import { describe, expect, it, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { CartProvider, useCart } from "./CartContext";
import type { Product } from "../api/types";

const mug: Product = {
  id: "p1",
  sku: "BDX-MUG-001",
  name: "Bedoux Ceramic Mug",
  description: "",
  category: "kitchen",
  price_cents: 1400,
  image_path: "/static/products/mug-001.svg",
};

const tote: Product = {
  id: "p2",
  sku: "BDX-TOTE-001",
  name: "Bedoux Canvas Tote",
  description: "",
  category: "bags",
  price_cents: 2200,
  image_path: "/static/products/tote-001.svg",
};

beforeEach(() => {
  window.localStorage.clear();
});

describe("CartContext", () => {
  it("adds an item and computes totals", () => {
    const { result } = renderHook(() => useCart(), { wrapper: CartProvider });

    act(() => result.current.addItem(mug, 2));

    expect(result.current.lines).toHaveLength(1);
    expect(result.current.totalItems).toBe(2);
    expect(result.current.totalCents).toBe(2800);
  });

  it("merges a repeated add into the same line instead of duplicating", () => {
    const { result } = renderHook(() => useCart(), { wrapper: CartProvider });

    act(() => result.current.addItem(mug, 1));
    act(() => result.current.addItem(mug, 1));

    expect(result.current.lines).toHaveLength(1);
    expect(result.current.lines[0].quantity).toBe(2);
  });

  it("computes a correct total across multiple distinct products", () => {
    const { result } = renderHook(() => useCart(), { wrapper: CartProvider });

    act(() => result.current.addItem(mug, 2));
    act(() => result.current.addItem(tote, 1));

    expect(result.current.totalCents).toBe(1400 * 2 + 2200 * 1);
    expect(result.current.totalItems).toBe(3);
  });

  it("setQuantity to zero removes the line", () => {
    const { result } = renderHook(() => useCart(), { wrapper: CartProvider });

    act(() => result.current.addItem(mug, 1));
    act(() => result.current.setQuantity(mug.id, 0));

    expect(result.current.lines).toHaveLength(0);
  });

  it("removeItem drops only the targeted line", () => {
    const { result } = renderHook(() => useCart(), { wrapper: CartProvider });

    act(() => result.current.addItem(mug, 1));
    act(() => result.current.addItem(tote, 1));
    act(() => result.current.removeItem(mug.id));

    expect(result.current.lines).toHaveLength(1);
    expect(result.current.lines[0].product.id).toBe(tote.id);
  });

  it("clear empties the cart", () => {
    const { result } = renderHook(() => useCart(), { wrapper: CartProvider });

    act(() => result.current.addItem(mug, 3));
    act(() => result.current.clear());

    expect(result.current.lines).toHaveLength(0);
    expect(result.current.totalCents).toBe(0);
  });

  it("persists the cart to localStorage across a remount", () => {
    const { result, unmount } = renderHook(() => useCart(), { wrapper: CartProvider });
    act(() => result.current.addItem(mug, 2));
    unmount();

    const { result: result2 } = renderHook(() => useCart(), { wrapper: CartProvider });
    expect(result2.current.lines).toHaveLength(1);
    expect(result2.current.lines[0].quantity).toBe(2);
  });
});
