import { readFileSync } from "node:fs";
import { it, expect } from "vitest";
import { priceCart, type ComboSelection } from "../src/pricing";
interface Vector {
  name: string;
  items: { id: string; product_id: string; price: number; quantity: number }[];
  combos: {
    rule: {
      id: string;
      version: string;
      name: string;
      price: number;
      parts: { product_id: string; quantity: number }[];
    };
    picks: string[];
    quantity: number;
  }[];
  expected: {
    regular_subtotal: number;
    subtotal: number;
    rounding_discount: number;
    amount: number;
    lines: Record<string, number[]>;
  };
}
const vectors = JSON.parse(
  readFileSync("../docs/test-vectors/combo-pricing.json", "utf8"),
) as Vector[];
for (const vector of vectors)
  it(`Tính giá dùng chung: ${vector.name}`, () => {
    const selections: ComboSelection[] = vector.combos.map((s) => ({
      ...s,
      rule: {
        ...s.rule,
        parts: s.rule.parts.map((p) => ({
          productId: p.product_id,
          quantity: p.quantity,
        })),
      },
    }));
    const result = priceCart(
      vector.items.map((i) => ({ ...i, productId: i.product_id })),
      selections,
    );
    expect({
      regular_subtotal: result.regularSubtotal,
      subtotal: result.subtotal,
      rounding_discount: result.roundingDiscount,
      amount: result.amount,
      lines: Object.fromEntries(
        [...result.lines].map(([id, v]) => [
          id,
          [v.amount, v.unitPrice, v.roundingDiscount],
        ]),
      ),
    }).toEqual(vector.expected);
  });
it("Không cho dùng một món thiếu số lượng hoặc sai sản phẩm để nhận combo", () => {
  const rule = {
    id: "set",
    version: "v1",
    name: "Bộ",
    price: 1,
    parts: [{ productId: "shirt", quantity: 2 }],
  };
  expect(() =>
    priceCart(
      [{ id: "a", productId: "shirt", price: 100, quantity: 1 }],
      [{ rule, picks: ["a"], quantity: 1 }],
    ),
  ).toThrow("thiếu");
  expect(() =>
    priceCart(
      [{ id: "a", productId: "hat", price: 100, quantity: 2 }],
      [{ rule, picks: ["a"], quantity: 1 }],
    ),
  ).toThrow("sản phẩm");
});
