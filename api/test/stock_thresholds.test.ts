import { it, expect } from "vitest";
import { fixture, actor } from "./report_fixtures";
import { push } from "../src/sync";
const id = (n: number) =>
  `019c4b00-0000-7000-8000-${String(n).padStart(12, "0")}`;
const rule = (
  n: number,
  threshold = 5,
  stamp = "2026-11-15T00:00:00.000Z",
) => ({
  id: id(n),
  store_id: "s1",
  device_id: "d1",
  user_id: "u1",
  variant_id: "v1",
  threshold,
  version_key: `${stamp}|d1|${id(n)}`,
  created_at: stamp,
});
const envelope = (n: number, row = rule(n)) => ({
  mutations: [
    { id: id(n + 100), records: [{ table: "stock_threshold_rules", row }] },
  ],
});
it("Ngưỡng đồng bộ idempotent, hội tụ khi nhận ngược thứ tự; không sửa giá cửa hàng", async () => {
  const { db, sqlite } = fixture();
  try {
    sqlite.exec("INSERT INTO store_variant_settings VALUES('s1','v1',90000,3)");
    await push(db, actor, envelope(2, rule(2, 9)));
    await push(db, actor, envelope(1, rule(1, 2)));
    await push(db, actor, envelope(2, rule(2, 9)));
    expect(
      sqlite
        .prepare(
          "SELECT low_stock_threshold,price_override FROM store_variant_settings",
        )
        .get(),
    ).toMatchObject({ low_stock_threshold: 9, price_override: 90000 });
    expect(
      sqlite.prepare("SELECT COUNT(*) n FROM stock_threshold_rules").get()?.n,
    ).toBe(2);
    expect(() =>
      sqlite.exec("UPDATE stock_threshold_rules SET threshold=1"),
    ).toThrow(/APPEND_ONLY/);
    expect(() => sqlite.exec("DELETE FROM stock_threshold_rules")).toThrow(
      /APPEND_ONLY/,
    );
  } finally {
    sqlite.close();
  }
});
it("Chặn sai scope, giả người dùng, giá trị lỗi, khóa phiên bản và quyền lúc cấp", async () => {
  const { db, sqlite } = fixture();
  try {
    for (const row of [
      { ...rule(1), store_id: "other" },
      { ...rule(1), user_id: "u2" },
      { ...rule(1), threshold: -1 },
      { ...rule(1), threshold: 1.5 },
      { ...rule(1), version_key: "fake" },
    ])
      await expect(push(db, actor, envelope(1, row))).rejects.toThrow();
    await expect(
      push(db, { ...actor, role: "cashier" }, envelope(1)),
    ).rejects.toThrow();
    await expect(
      push(db, { ...actor, issued_role: "cashier" }, envelope(1)),
    ).rejects.toThrow();
    expect(
      sqlite.prepare("SELECT COUNT(*) n FROM stock_threshold_rules").get()?.n,
    ).toBe(0);
  } finally {
    sqlite.close();
  }
});
it("Lỗi cuối batch rollback cả ngưỡng, cache và ACK", async () => {
  const { db, sqlite } = fixture();
  try {
    sqlite.exec(
      "CREATE TRIGGER fail_threshold_feed BEFORE INSERT ON change_feed WHEN NEW.entity_type='stock_threshold_rules' BEGIN SELECT RAISE(ABORT,'fixture fail'); END;",
    );
    await expect(push(db, actor, envelope(1))).rejects.toThrow();
    for (const table of [
      "stock_threshold_rules",
      "store_variant_settings",
      "processed_mutations",
    ])
      expect(sqlite.prepare(`SELECT COUNT(*) n FROM ${table}`).get()?.n).toBe(
        0,
      );
  } finally {
    sqlite.close();
  }
});
