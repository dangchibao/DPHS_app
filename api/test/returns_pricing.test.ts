import { readFileSync } from "node:fs";
import { it, expect } from "vitest";
import {
  returnCredit,
  exchangeLine,
  settleReturn,
  priceReplacements,
} from "../src/returns_pricing";
it("Đổi sản phẩm khác theo giá mới, không dùng nhầm giá ưu đãi của món gốc", () => {
  const old = new Map([
      ["old", { product_id: "p1", quantity: 1, credit: 100000 }],
    ]),
    variants = new Map([["v2", { product_id: "p2", price: 120000 }]]);
  expect(
    priceReplacements(
      [{ variant_id: "v2", quantity: 1, source_line_id: null }],
      old,
      variants,
    ).get("v2"),
  ).toMatchObject({ amount: 120000, unit_price: 120000, discount: 0 });
  expect(() =>
    priceReplacements(
      [{ variant_id: "v2", quantity: 1, source_line_id: "old" }],
      old,
      variants,
    ),
  ).toThrow("cùng sản phẩm");
});
const vectors = JSON.parse(
  readFileSync("../docs/test-vectors/return-settlement.json", "utf8"),
) as Record<string, unknown>[];
for (const v of vectors)
  it(String(v.name), () => {
    const run = () =>
      settleReturn(
        Number(v.balance),
        Number(v.returned),
        Number(v.replacement),
        Number(v.received),
      );
    if (v.reject) expect(run).toThrow();
    else {
      const result = run();
      expect([
        result.debt_offset,
        result.cash_due,
        result.refund,
        result.new_debt,
      ]).toEqual([v.offset, v.due, v.refund, v.debt]);
    }
  });
it("Trả từng phần cộng đúng tổng giảm/combo, không hoàn thừa một đồng", () => {
  const values = [0, 1, 2].map((before) => returnCredit(100001, 3, before, 1));
  expect(values).toEqual([33333, 33334, 33334]);
  expect(values.reduce((a, b) => a + b, 0)).toBe(100001);
  expect(() => returnCredit(100001, 3, 2, 2)).toThrow();
  expect(exchangeLine(100001, 3)).toEqual({ unit_price: 33334, discount: 1 });
  expect(
    returnCredit(Number.MAX_SAFE_INTEGER, 100000, 99999, 1),
  ).toBeGreaterThan(0);
});
