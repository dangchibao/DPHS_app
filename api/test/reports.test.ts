import { it, expect } from "vitest";
import { fixture, actor, sale, apply, metrics } from "./report_fixtures";
import { refreshReports } from "../src/report_refresh";
import type { SyncRecord } from "../src/sync";
import {
  reportDaily,
  reportDetails,
  reportOptions,
  rebuildReports,
} from "../src/reports";
const url = (params: Record<string, string>) => {
  const u = new URL("https://test/reports/daily");
  for (const [k, v] of Object.entries({
    from: "2026-11-01",
    to: "2026-11-30",
    ...params,
  }))
    u.searchParams.set(k, v);
  return u;
};
it("Làm mới nhóm thay đổi sau trang đầu: thay thế thay vì cộng trùng, bắt cả bucket mới trước cursor", async () => {
  const d = fixture();
  try {
    await apply(d, sale("base"));
    const baseline = (await (
      await reportDaily(d.db, actor, url({}))
    ).json()) as { rows: Record<string, unknown>[]; feed_cursor: string };
    for (const [id, stamp] of [
      ["before", "2026-11-14T00:00:00.000Z"],
      ["same", "2026-11-15T00:00:00.000Z"],
    ]) {
      const records: SyncRecord[] = sale(id).map((r) => ({
        table: r.table,
        row: {
          ...r.row,
          ...(r.table === "documents"
            ? { issued_at: stamp }
            : r.table === "payments"
              ? { created_at: stamp }
              : {}),
        },
      }));
      await apply(d, records);
      for (const r of records.filter(
        (r) => r.table === "documents" || r.table === "payments",
      ))
        d.sqlite
          .prepare(
            "INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) VALUES(?,?,?,?,?,?)",
          )
          .run(
            "s1",
            id,
            r.table,
            String(r.row.id),
            JSON.stringify(r.row),
            stamp,
          );
    }
    const refreshed = (await (
      await refreshReports(d.db, actor, url({ since: baseline.feed_cursor }))
    ).json()) as { rows: Record<string, unknown>[] };
    expect(refreshed.rows).toHaveLength(2);
    const map = new Map(
      [...baseline.rows, ...refreshed.rows].map((r) => [
        JSON.stringify([r.store_id, r.day, r.school_year, r.school_id]),
        r,
      ]),
    );
    expect(
      Array.from(map.values()).reduce(
        (sum, row) =>
          sum + BigInt((row.metrics as Record<string, string>).revenue),
        0n,
      ),
    ).toBe(600000n);
    await expect(
      refreshReports(d.db, actor, url({ since: "bad" })),
    ).rejects.toThrow();
    d.sqlite.exec("INSERT INTO report_cache_state VALUES('s1',1)");
    await expect(
      refreshReports(d.db, actor, url({ since: "0" })),
    ).rejects.toThrow("dữ liệu cũ");
  } finally {
    d.sqlite.close();
  }
});
it("Report scope owner/all, manager chỉ store; issued role không tự nâng quyền", async () => {
  const d = fixture();
  try {
    await apply(d, sale());
    d.sqlite.exec(
      "INSERT INTO employee_store_assignments VALUES('a1','s1','u1','owner',1,'2026-11-15'); INSERT INTO stores VALUES('s2','NT-CN02','CN02',1,'2026-11-15'); INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d2','s2','B3','Máy 2','approved','2026-11-15');",
    );
    const other = sale("other").map((r) => ({
      table: r.table,
      row: {
        ...r.row,
        store_id: "s2",
        ...(Object.hasOwn(r.row, "device_id") ? { device_id: "d2" } : {}),
      },
    }));
    await apply(d, other, { ...actor, store_id: "s2", device_id: "d2" });
    const all = (await (
      await reportDaily(d.db, actor, url({ store: "all" }))
    ).json()) as {
      rows: { store_id: string; metrics: Record<string, string> }[];
    };
    expect(all.rows.map((r) => r.store_id)).toEqual(["s1", "s2"]);
    expect(all.rows.map((r) => r.metrics.revenue)).toEqual([
      "200000",
      "200000",
    ]);
    const manager = {
      ...actor,
      role: "manager" as const,
      issued_role: "manager" as const,
    };
    expect(
      (
        (await (await reportDaily(d.db, manager, url({}))).json()) as {
          rows: unknown[];
        }
      ).rows,
    ).toHaveLength(1);
    await expect(
      reportDaily(d.db, manager, url({ store: "s2" })),
    ).rejects.toThrow();
    await expect(
      reportDaily(d.db, manager, url({ store: "all" })),
    ).rejects.toThrow();
    await expect(
      reportDaily(
        d.db,
        { ...actor, issued_role: "manager" },
        url({ store: "all" }),
      ),
    ).rejects.toThrow();
    const opts = (await (await reportOptions(d.db, manager)).json()) as {
      stores: unknown[];
      can_all_stores: boolean;
    };
    expect(opts.stores).toHaveLength(1);
    expect(opts.can_all_stores).toBe(false);
  } finally {
    d.sqlite.close();
  }
});
it("Daily cursor/date/year/school filters không mất/lặp trang, trả số dạng chuỗi nguyên", async () => {
  const d = fixture();
  try {
    for (let i = 1; i <= 27; i++) {
      const stamp = `2026-10-${String(i).padStart(2, "0")}T00:00:00.000Z`;
      await apply(
        d,
        sale(`hd${i}`).map((r) => ({
          table: r.table,
          row: {
            ...r.row,
            ...(r.table === "documents"
              ? {
                  issued_at: stamp,
                  metadata_json: JSON.stringify({
                    school_id: i % 2 ? "schoolA" : "schoolB",
                  }),
                }
              : r.table === "payments"
                ? { created_at: stamp }
                : {}),
          },
        })),
      );
    }
    const first = (await (
      await reportDaily(
        d.db,
        actor,
        url({ from: "2026-10-01", to: "2026-10-31" }),
      )
    ).json()) as {
      rows: { day: string; metrics: Record<string, string> }[];
      next_cursor: string;
    };
    expect(first.rows).toHaveLength(25);
    expect(first.rows[0].metrics.revenue).toBe("200000");
    const next = (await (
      await reportDaily(
        d.db,
        actor,
        url({
          from: "2026-10-01",
          to: "2026-10-31",
          cursor: first.next_cursor,
        }),
      )
    ).json()) as { rows: { day: string }[]; next_cursor: null };
    expect(next.rows).toHaveLength(2);
    expect(next.next_cursor).toBeNull();
    expect(new Set([...first.rows, ...next.rows].map((r) => r.day)).size).toBe(
      27,
    );
    const filtered = (await (
      await reportDaily(
        d.db,
        actor,
        url({
          from: "2026-10-01",
          to: "2026-10-31",
          school: "schoolA",
          year: "2026–2027",
        }),
      )
    ).json()) as { rows: unknown[] };
    expect(filtered.rows).toHaveLength(14);
    await expect(
      reportDaily(d.db, actor, url({ from: "2026-02-30" })),
    ).rejects.toThrow();
    await expect(
      reportDaily(d.db, actor, url({ cursor: "garbage" })),
    ).rejects.toThrow();
  } finally {
    d.sqlite.close();
  }
});
it("Legacy rebuild + thu tiền trong lúc chuẩn bị không đếm lặp; current debt cache và nhãn thời điểm rõ", async () => {
  const d = fixture();
  try {
    d.sqlite.exec(
      "INSERT INTO employee_store_assignments VALUES('a1','s1','u1','owner',1,'2026-11-15'); INSERT INTO customers(id,store_id,name,updated_at) VALUES('c1','s1','Phụ huynh','2026-11-15');",
    );
    const records = sale().map((r) =>
      r.table === "documents"
        ? { table: r.table, row: { ...r.row, customer_id: "c1" } }
        : r,
    );
    for (const r of records)
      d.sqlite
        .prepare(
          `INSERT INTO ${r.table} (${Object.keys(r.row).join(",")}) VALUES (${Object.keys(
            r.row,
          )
            .map(() => "?")
            .join(",")})`,
        )
        .run(...(Object.values(r.row) as (string | number | null)[]));
    d.sqlite.exec(
      "INSERT INTO receivable_entries VALUES('debt','s1','c1','hd',NULL,100000,'2026-11-16','2026-11-15T00:00:00.000Z'); INSERT INTO report_cache_state VALUES('s1',1);",
    );
    await expect(reportDaily(d.db, actor, url({}))).rejects.toThrow(
      "dữ liệu cũ",
    );
    const payment = {
      ...records[2].row,
      id: "pay2",
      amount: 50000,
      created_at: "2026-11-16T00:00:00.000Z",
    };
    await apply(d, [
      { table: "payments", row: payment },
      {
        table: "receivable_entries",
        row: {
          id: "collect",
          store_id: "s1",
          customer_id: "c1",
          document_id: "hd",
          payment_id: "pay2",
          amount: -50000,
          due_date: "",
          created_at: payment.created_at,
        },
      },
    ]);
    const rebuilt = (await (
      await rebuildReports(d.db, actor, { store_id: "s1" })
    ).json()) as { has_more: boolean };
    expect(rebuilt.has_more).toBe(false);
    await rebuildReports(d.db, actor, { store_id: "s1" });
    const daily = (await (await reportDaily(d.db, actor, url({}))).json()) as {
      rows: { metrics: Record<string, string> }[];
    };
    expect(
      daily.rows.reduce((s, r) => s + BigInt(r.metrics.revenue ?? 0), 0n),
    ).toBe(200000n);
    expect(
      daily.rows.reduce((s, r) => s + BigInt(r.metrics.payment_in ?? 0), 0n),
    ).toBe(150000n);
    const debts = (await (
      await reportDetails(d.db, actor, url({ kind: "debts" }))
    ).json()) as { rows: { amount: string }[]; as_of: string };
    expect(debts.rows[0].amount).toBe("50000");
    expect(debts.as_of).toBe("current");
    await expect(
      rebuildReports(d.db, { ...actor, role: "manager" }, { store_id: "s1" }),
    ).rejects.toThrow();
  } finally {
    d.sqlite.close();
  }
});
it("Overflow cache không đưa số sai vào báo cáo; stock trả nguyên số thay vì float", async () => {
  const d = fixture();
  try {
    await apply(d, sale("huge", 100000, 9007199254740991));
    expect(metrics(d).revenue).toBe("10000000000");
    await expect(reportDaily(d.db, actor, url({}))).rejects.toThrow(
      "giới hạn an toàn",
    );
    const stock = (await (
      await reportDetails(d.db, actor, url({ kind: "stock" }))
    ).json()) as {
      rows: { quantity: string; unit_cost: string }[];
      as_of: string;
    };
    expect(stock.as_of).toBe("current");
    expect(stock.rows[0].quantity).toBe("0");
    expect(stock.rows[0].unit_cost).toBe("50000");
  } finally {
    d.sqlite.close();
  }
});
