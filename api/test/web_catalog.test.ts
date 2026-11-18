import { it, expect } from "vitest";
import { fixture, actor } from "./report_fixtures";
import { webCatalog } from "../src/web_catalog";
const stamp = "2026-11-15T12:00:00.000Z";
const id = (n: number) =>
  `019c4b00-0000-7000-8000-${String(n).padStart(12, "0")}`;
const url = new URL("https://fixture.test/web/catalog");
function setup() {
  const f = fixture();
  f.sqlite.exec(
    "INSERT INTO devices(id,store_id,code,name,status,created_at,kind) VALUES('web','s1','W1','Web','approved','2026-11-15','web')",
  );
  return {
    ...f,
    a: {
      ...actor,
      device_id: "web",
      device_kind: "web" as const,
      session_kind: "interactive" as const,
    },
  };
}
function body(f: ReturnType<typeof setup>) {
  const p = f.sqlite.prepare("SELECT * FROM products WHERE id=?").get("p1")!,
    v = f.sqlite
      .prepare("SELECT * FROM product_variants WHERE id=?")
      .get("v1")!;
  const key = `${stamp}|web|${id(1)}`;
  return {
    id: id(1),
    reason: "Cập nhật thử",
    records: [
      {
        table: "products",
        row: { ...p, updated_at: stamp, lww_key: key, version: 2 },
      },
      {
        table: "product_variants",
        row: {
          ...v,
          price: 125000,
          updated_at: stamp,
          lww_key: key,
          version: 2,
        },
      },
      {
        table: "stock_threshold_rules",
        row: {
          id: id(2),
          store_id: "s1",
          device_id: "web",
          user_id: "u1",
          variant_id: "v1",
          threshold: 8,
          version_key: `${stamp}|web|${id(2)}`,
          created_at: stamp,
        },
      },
    ],
  };
}
it("Web lưu danh mục/ngưỡng và audit nguyên tử, retry không lặp; giá lịch sử có snapshot", async () => {
  const f = setup();
  try {
    const data = body(f);
    await webCatalog(f.db, f.a, url, data);
    await webCatalog(f.db, f.a, url, data);
    expect(
      f.sqlite
        .prepare("SELECT price FROM product_variants WHERE id=?")
        .get("v1")?.price,
    ).toBe(125000);
    expect(
      f.sqlite
        .prepare("SELECT low_stock_threshold FROM store_variant_settings")
        .get()?.low_stock_threshold,
    ).toBe(8);
    expect(
      f.sqlite
        .prepare(
          "SELECT COUNT(*) n FROM audit_logs WHERE action='PRODUCT_WEB_SAVE'",
        )
        .get()?.n,
    ).toBe(1);
    expect(
      f.sqlite
        .prepare(
          "SELECT COUNT(*) n FROM variant_price_history WHERE price=125000",
        )
        .get()?.n,
    ).toBe(1);
    expect(
      f.sqlite.prepare("SELECT COUNT(*) n FROM stock_movements").get()?.n,
    ).toBe(0);
    const list = (await (await webCatalog(f.db, f.a, url)).json()) as {
      rows: { price: number }[];
    };
    expect(list.rows[0].price).toBe(125000);
  } finally {
    f.sqlite.close();
  }
});
it("Web không nhận ledger hoặc audit giả, chặn quyền thấp/issued role và rollback khi audit lỗi", async () => {
  const f = setup();
  try {
    const data = body(f);
    await expect(
      webCatalog(f.db, { ...f.a, role: "cashier" }, url, data),
    ).rejects.toThrow();
    await expect(
      webCatalog(f.db, { ...f.a, issued_role: "cashier" }, url, data),
    ).rejects.toThrow();
    for (const table of [
      "stock_movements",
      "audit_logs",
      "payments",
      "employee_store_assignments",
    ])
      await expect(
        webCatalog(f.db, f.a, url, {
          ...data,
          records: [...data.records.slice(0, 2), { table, row: {} }],
        }),
      ).rejects.toThrow();
    f.sqlite.exec(
      "CREATE TRIGGER fail_web_catalog BEFORE INSERT ON audit_logs WHEN NEW.action='PRODUCT_WEB_SAVE' BEGIN SELECT RAISE(ABORT,'fixture'); END",
    );
    await expect(webCatalog(f.db, f.a, url, data)).rejects.toThrow();
    expect(
      f.sqlite
        .prepare("SELECT price FROM product_variants WHERE id=?")
        .get("v1")?.price,
    ).toBe(100000);
    expect(
      f.sqlite.prepare("SELECT COUNT(*) n FROM stock_threshold_rules").get()?.n,
    ).toBe(0);
    expect(
      f.sqlite.prepare("SELECT COUNT(*) n FROM processed_mutations").get()?.n,
    ).toBe(0);
  } finally {
    f.sqlite.close();
  }
});
