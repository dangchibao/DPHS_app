import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { push, pull } from "../src/sync";
import { sha256 } from "../src/security";
import type { Actor } from "../src/auth";

it("Nhật ký nhận timestamp máy chủ một lần, gửi lặp giữ nguyên; cursor audit độc lập", async () => {
  const { db, sqlite } = testDatabase();
  const actor: Actor = {
    user_id: "u1",
    store_id: "s1",
    device_id: "d1",
    role: "owner",
    name: "Chủ",
    session_id: "session",
  };
  try {
    sqlite.exec(`INSERT INTO stores VALUES ('s1','NT-CN01','CN01',1,'2026-11-15');
      INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d1','s1','A2','Máy','approved','2026-11-15');
      INSERT INTO users VALUES ('u1','admin','Chủ','hash','salt',1,0,'2026-11-15');`);
    const canonical = {
      id: "audit-1",
      store_id: "s1",
      device_id: "d1",
      user_id: "u1",
      role: "owner",
      action: "LOGIN",
      entity_type: "user",
      entity_id: "u1",
      changes: {},
      reason: "Đăng nhập",
      client_time: "2026-11-15T00:00:00.000Z",
      severity: "normal",
      hash_prev: "",
      chain_index: 1,
    };
    const { changes, ...fields } = canonical;
    const row = {
      ...fields,
      changes_json: JSON.stringify(changes),
      document_code: null,
      server_time: null,
      app_version: "0.1.0",
      hash: await sha256(JSON.stringify(canonical)),
    };
    const body = {
      mutations: [{ id: "job-audit", records: [{ table: "audit_logs", row }] }],
    };
    await push(db, actor, body);
    const saved = sqlite
      .prepare("SELECT * FROM audit_logs WHERE id='audit-1'")
      .get()!;
    expect(saved.server_time).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    expect(saved.hash).toBe(row.hash);
    await push(db, actor, body);
    await push(db, actor, {
      mutations: [{ ...body.mutations[0], id: "job-audit-again" }],
    });
    expect(
      sqlite
        .prepare("SELECT server_time FROM audit_logs WHERE id='audit-1'")
        .get()?.server_time,
    ).toBe(saved.server_time);
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM audit_logs").get()?.n,
    ).toBe(1);
    await expect(
      push(db, actor, {
        mutations: [
          {
            id: "forged-time",
            records: [
              {
                table: "audit_logs",
                row: { ...row, server_time: "2020-01-01" },
              },
            ],
          },
        ],
      }),
    ).rejects.toThrow();
    const cashier = { ...actor, role: "cashier" as const };
    const general = (await (
      await pull(db, cashier, new URL("http://localhost/sync/pull?cursor=0"))
    ).json()) as { events: unknown[]; cursor: number };
    expect(general.events).toHaveLength(0);
    expect(general.cursor).toBeGreaterThan(0);
    await expect(
      pull(
        db,
        cashier,
        new URL("http://localhost/sync/pull?scope=audit&cursor=0"),
      ),
    ).rejects.toThrow("quyền");
    const audits = (await (
      await pull(
        db,
        actor,
        new URL("http://localhost/sync/pull?scope=audit&cursor=0"),
      )
    ).json()) as { events: unknown[]; cursor: number };
    expect(audits.events.length).toBeGreaterThan(0);
    expect(audits.cursor).toBe(general.cursor);
  } finally {
    sqlite.close();
  }
});
