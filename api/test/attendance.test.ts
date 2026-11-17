import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { push, pull, type SyncRecord } from "../src/sync";
import type { Actor } from "../src/auth";
const now = new Date().toISOString(),
  day = new Date(Date.parse(now) + 7 * 3600000).toISOString().slice(0, 10);
const actor: Actor = {
  user_id: "u1",
  store_id: "s1",
  device_id: "d1",
  role: "manager",
  name: "Quản lý",
  session_id: "session",
};
function fixture() {
  const d = testDatabase();
  d.sqlite.exec(
    `INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'${now}');INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','${now}');INSERT INTO users VALUES('u1','manager','Quản lý','hash','salt',1,0,'${now}'),('u2','cashier','Nhân viên','hash','salt',1,0,'${now}');INSERT INTO employee_store_assignments VALUES('a1','s1','u1','manager',1,'${now}'),('a2','s1','u2','cashier',1,'${now}');`,
  );
  return d;
}
function entry(id = "e1", units = 2): SyncRecord {
  return {
    table: "attendance_entries",
    row: {
      id,
      store_id: "s1",
      device_id: "d1",
      user_id: "u1",
      employee_id: "u2",
      work_day: day,
      day_units: units,
      reason: "Đã kiểm tra ngày công",
      created_at: now,
      lww_key: `${now}|d1|${id}`,
    },
  };
}
const send = (db: D1Database, id: string, r = entry(), a = actor) =>
  push(db, a, { mutations: [{ id, records: [r] }] });
it("Chấm công append-only, feed riêng và quyền current/issued", async () => {
  const d = fixture();
  try {
    await expect(
      send(d.db, "cashier", entry(), { ...actor, role: "cashier" }),
    ).rejects.toThrow();
    await expect(
      send(d.db, "old-role", entry(), { ...actor, issued_role: "cashier" }),
    ).rejects.toThrow();
    await send(d.db, "mark");
    await send(d.db, "mark");
    const publicFeed = (await (
      await pull(
        d.db,
        { ...actor, role: "cashier" },
        new URL("https://test/sync/pull?cursor=0"),
      )
    ).json()) as { events: unknown[]; cursor: number };
    expect(publicFeed.events).toHaveLength(0);
    expect(publicFeed.cursor).toBeGreaterThan(0);
    const privateFeed = (await (
      await pull(
        d.db,
        actor,
        new URL("https://test/sync/pull?scope=attendance&cursor=0"),
      )
    ).json()) as { events: { entity_type: string }[] };
    expect(privateFeed.events.map((r) => r.entity_type)).toEqual([
      "attendance_entries",
    ]);
    await expect(
      pull(
        d.db,
        { ...actor, role: "cashier" },
        new URL("https://test/sync/pull?scope=attendance"),
      ),
    ).rejects.toThrow();
    expect(() =>
      d.sqlite.exec("UPDATE attendance_entries SET day_units=0 WHERE id='e1'"),
    ).toThrow("append-only");
  } finally {
    d.sqlite.close();
  }
});
it("Event offline tới sau khóa kỳ được ACK/reject rõ, không đổi công đã chốt", async () => {
  const d = fixture();
  try {
    await send(d.db, "first");
    d.sqlite
      .prepare("INSERT INTO payroll_locks VALUES(?,?,?,?,?,?,?)")
      .run("lock", "s1", "u2", "run", "2026-01-01", "2027-01-01", now);
    await send(d.db, "first-replay");
    const response = (await (
      await send(d.db, "late", entry("e2", 0))
    ).json()) as { acknowledged: string[] };
    expect(response.acknowledged).toEqual(["late"]);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM attendance_entries").get()?.n,
    ).toBe(1);
    expect(
      d.sqlite.prepare("SELECT id FROM attendance_rejections").get()?.id,
    ).toBe("e2");
    await send(d.db, "late-replay", entry("e2", 0));
    d.sqlite
      .prepare("INSERT INTO payroll_lock_releases VALUES(?,?,?,?)")
      .run("release", "s1", "run", now);
    await send(d.db, "still-rejected", entry("e2", 0));
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM attendance_entries").get()?.n,
    ).toBe(1);
    await send(d.db, "new-correction", entry("e3", 1));
    expect(
      d.sqlite
        .prepare(
          "SELECT day_units FROM attendance_entries ORDER BY lww_key DESC LIMIT 1",
        )
        .get()?.day_units,
    ).toBe(1);
  } finally {
    d.sqlite.close();
  }
});
it("Chặn ngày sai, công lẻ ngoài quy định, người ngoài store và sửa ID đã từ chối", async () => {
  const d = fixture();
  try {
    for (const [field, value] of [
      ["work_day", "2026-02-30"],
      ["day_units", 1.5],
      ["employee_id", "unknown"],
      ["lww_key", "future"],
    ] as const) {
      const r = entry();
      r.row[field] = value;
      await expect(send(d.db, field, r)).rejects.toThrow();
    }
    d.sqlite
      .prepare("INSERT INTO payroll_locks VALUES(?,?,?,?,?,?,?)")
      .run("lock", "s1", "u2", "run", "2026-01-01", "2027-01-01", now);
    await send(d.db, "rejected");
    await expect(send(d.db, "changed", entry("e1", 1))).rejects.toThrow(
      "nội dung khác",
    );
  } finally {
    d.sqlite.close();
  }
});
