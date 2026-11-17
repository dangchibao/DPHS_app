import { it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { redactAuditChanges } from "../src/audit_redaction";
import { testDatabase } from "./database";
import { push } from "../src/sync";
import { sha256 } from "../src/security";
import type { Actor } from "../src/auth";
const vectors = JSON.parse(
  readFileSync("../docs/test-vectors/audit-redaction.json", "utf8"),
) as {
  name: string;
  action: string;
  changes: Record<string, unknown>;
  expected: unknown;
}[];
for (const v of vectors)
  it(v.name, () =>
    expect(redactAuditChanges(v.changes, v.action)).toEqual(v.expected),
  );
it("API từ chối audit bí mật dù hash hợp lệ; không tự sửa chain client", async () => {
  const d = testDatabase();
  try {
    const now = new Date().toISOString();
    d.sqlite.exec(
      `INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'${now}');INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','${now}');INSERT INTO users VALUES('u1','admin','Chủ','hash','salt',1,0,'${now}');`,
    );
    const actor: Actor = {
      user_id: "u1",
      store_id: "s1",
      device_id: "d1",
      role: "owner",
      name: "Chủ",
      session_id: "session",
    };
    const raw = { employee_id: "u1", amount: 10000000 };
    const send = async (id: string, changes: Record<string, unknown>) => {
      const canonical = {
        id: "audit",
        store_id: "s1",
        device_id: "d1",
        user_id: "u1",
        role: "owner",
        action: "PAYROLL_RULE_SAVE",
        entity_type: "employee",
        entity_id: "u1",
        changes,
        reason: "Thay cấu hình",
        client_time: now,
        severity: "sensitive",
        hash_prev: "",
        chain_index: 1,
      };
      const { changes: _, ...fields } = canonical;
      void _;
      return push(d.db, actor, {
        mutations: [
          {
            id,
            records: [
              {
                table: "audit_logs",
                row: {
                  ...fields,
                  changes_json: JSON.stringify(changes),
                  document_code: null,
                  server_time: null,
                  app_version: "0.5.0",
                  hash: await sha256(JSON.stringify(canonical)),
                },
              },
            ],
          },
        ],
      });
    };
    await expect(send("raw", raw)).rejects.toMatchObject({
      code: "AUDIT_SENSITIVE",
    });
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM audit_logs").get()?.n,
    ).toBe(0);
    await send("masked", redactAuditChanges(raw, "PAYROLL_RULE_SAVE"));
    expect(
      d.sqlite.prepare("SELECT changes_json FROM audit_logs").get()
        ?.changes_json,
    ).not.toContain("10000000");
  } finally {
    d.sqlite.close();
  }
});
