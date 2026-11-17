import { readFileSync } from "node:fs";
import { it, expect } from "vitest";
import {
  parseRule,
  eligible,
  promotionDiscount,
  priceListItems,
} from "../src/commercial";
export const defaultConfig = {
  school_id: null,
  customer_kind: null,
  starts_at: null,
  ends_at: null,
  min_total: 0,
  min_quantity: 1,
  allow_combo: false,
  allow_price_list: false,
  prices: {},
  discount_type: "fixed",
  value: 1000,
  voucher: "",
};
const vectors = JSON.parse(
  readFileSync("../docs/test-vectors/commercial-pricing.json", "utf8"),
) as Record<string, unknown>[];
for (const v of vectors)
  it(String(v.name), () => {
    const run = () => {
      const rule = parseRule({
        id: "r1",
        lww_key: "version",
        name: "Ưu đãi",
        kind: "promotion",
        config_json: JSON.stringify({
          ...defaultConfig,
          ...(v.config as object),
        }),
      });
      eligible(
        rule,
        {
          school: v.school,
          customerKind: v.customerKind,
          issuedAt: "2026-11-15T00:00:00.000Z",
          quantity: Number(v.quantity ?? 1),
          amount: Number(v.amount),
          combos: v.combos === true,
        },
        String(v.voucher ?? ""),
      );
      return promotionDiscount(
        rule,
        Number(v.amount),
        Number(v.manual ?? 0),
        v.priceList === true,
      );
    };
    if (v.reject) expect(run).toThrow();
    else expect(run()).toBe(v.expected);
  });
it("Bảng giá chỉ đổi biến thể khai báo và giữ giá chung món khác", () => {
  const rule = parseRule({
    id: "r1",
    lww_key: "v",
    name: "Giá trường",
    kind: "price_list",
    config_json: JSON.stringify({
      ...defaultConfig,
      discount_type: "none",
      value: 0,
      prices: { v1: 80000 },
    }),
  });
  expect(
    priceListItems(rule, [
      { id: "v1", productId: "p1", price: 100000, quantity: 1 },
      { id: "v2", productId: "p1", price: 120000, quantity: 2 },
    ]).map((i) => i.price),
  ).toEqual([80000, 120000]);
});
it("Từ chối cấu hình ngoài schema, giá lẻ, phần trăm quá 100 và JSON lỗi", () => {
  for (const config of [
    { ...defaultConfig, extra: 1 },
    { ...defaultConfig, value: 1.5 },
    { ...defaultConfig, discount_type: "percent", value: 10001 },
  ])
    expect(() =>
      parseRule({
        id: "r",
        lww_key: "v",
        name: "Sai",
        kind: "promotion",
        config_json: JSON.stringify(config),
      }),
    ).toThrow();
  expect(() => parseRule({ config_json: "{" })).toThrow();
});
