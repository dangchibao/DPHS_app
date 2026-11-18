import { it, expect } from "vitest";
import { fixture, actor } from "./report_fixtures";
import { auditRead } from "../src/audit_reader";
const url = (query = "") =>
  new URL(
    `https://fixture.test/audit/read?from=2026-11-15&to=2026-11-15&${query}`,
  );
function seed(
  sqlite: ReturnType<typeof fixture>["sqlite"],
  store = "s1",
  device = "d1",
  count = 1,
) {
  for (let i = 1; i <= count; i++)
    sqlite
      .prepare(
        "INSERT INTO audit_logs VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      )
      .run(
        `${store}-${i}`,
        store,
        device,
        "u1",
        "owner",
        i === count ? "MATCH" : "OTHER",
        "document",
        `hd-${i}`,
        null,
        "{}",
        "Fixture",
        "2026-11-15T00:00:00.000Z",
        null,
        "0.6.0",
        "normal",
        "",
        "hash",
        i,
      );
}
it("Chủ xem toàn hệ thống; quản lý chỉ cửa hàng mình và không được dùng quyền mới vượt quyền lúc cấp", async () => {
  const { db, sqlite } = fixture();
  try {
    sqlite.exec(
      "INSERT INTO stores VALUES('s2','NT-CN02','CN02',1,'2026-11-15'); INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d2','s2','B2','Máy','approved','2026-11-15')",
    );
    seed(sqlite);
    seed(sqlite, "s2", "d2");
    expect(
      (
        (await (await auditRead(db, actor, url("store=all"))).json()) as {
          rows: unknown[];
        }
      ).rows.length,
    ).toBe(2);
    for (const a of [
      { ...actor, role: "manager" as const },
      { ...actor, issued_role: "manager" as const },
    ]) {
      await expect(auditRead(db, a, url("store=all"))).rejects.toThrow();
      await expect(auditRead(db, a, url("store=s2"))).rejects.toThrow();
      expect(
        ((await (await auditRead(db, a, url())).json()) as { rows: unknown[] })
          .rows.length,
      ).toBe(1);
    }
    await expect(
      auditRead(db, { ...actor, role: "cashier" }, url()),
    ).rejects.toThrow();
    const opts = (await (
      await auditRead(db, actor, new URL("https://fixture.test/audit/options"))
    ).json()) as { stores: unknown[] };
    expect(opts.stores.length).toBe(2);
  } finally {
    sqlite.close();
  }
});
it("Phân trang keyset không bỏ/trùng thời gian bằng nhau, bộ lọc rỗng vẫn tiến cursor, mỗi request đọc tối đa 201", async () => {
  const { db, sqlite } = fixture();
  try {
    seed(sqlite, "s1", "d1", 230);
    const seen = new Set<string>();
    let cursor = "";
    let pages = 0;
    while (true) {
      const data = (await (
        await auditRead(
          db,
          actor,
          url(`cursor=${encodeURIComponent(cursor || '["","",""]')}`),
        )
      ).json()) as {
        rows: { id: string }[];
        has_more: boolean;
        cursor: string;
        scanned: number;
      };
      expect(data.rows.length).toBeLessThanOrEqual(50);
      expect(data.scanned).toBeLessThanOrEqual(200);
      for (const r of data.rows) {
        expect(seen.has(r.id)).toBe(false);
        seen.add(r.id);
      }
      pages++;
      if (!data.has_more) break;
      cursor = data.cursor;
      expect(pages).toBeLessThan(10);
    }
    expect(seen.size).toBe(230);
    const empty = (await (
      await auditRead(db, actor, url("action=NOT_FOUND"))
    ).json()) as {
      rows: unknown[];
      has_more: boolean;
      cursor: string;
      scanned: number;
    };
    expect(empty.rows).toEqual([]);
    expect(empty.scanned).toBe(200);
    expect(empty.has_more).toBe(true);
    const last = (await (
      await auditRead(
        db,
        actor,
        url(`action=NOT_FOUND&cursor=${encodeURIComponent(empty.cursor)}`),
      )
    ).json()) as { has_more: boolean };
    expect(last.has_more).toBe(false);
    await expect(auditRead(db, actor, url("cursor=bad"))).rejects.toThrow();
    await expect(
      auditRead(
        db,
        actor,
        new URL(
          "https://fixture.test/audit/read?from=2026-01-01&to=2026-12-31",
        ),
      ),
    ).rejects.toThrow();
    const plan = sqlite
      .prepare(
        "EXPLAIN QUERY PLAN SELECT * FROM audit_logs WHERE store_id=? AND client_time>=? AND client_time<? ORDER BY store_id,client_time,id LIMIT 201",
      )
      .all("s1", "2026-11-14", "2026-11-16");
    expect(JSON.stringify(plan)).toContain("audit_store_time_id");
  } finally {
    sqlite.close();
  }
});
