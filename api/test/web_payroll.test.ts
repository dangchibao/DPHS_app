import { it, expect } from "vitest";
import { fixture, actor } from "./report_fixtures";
import { webPayroll } from "../src/web_payroll";
it("Lương online giới hạn cửa hàng, quyền hiện tại/issued và ghi audit khi đọc", async () => {
  const { db, sqlite } = fixture();
  try {
    sqlite.exec(
      "INSERT INTO employee_store_assignments VALUES('a1','s1','u1','owner',1,'2026-11-15')",
    );
    const url = new URL(
      "https://fixture.test/web/payroll?employee_id=u1&month=2026-11",
    );
    for (const a of [
      { ...actor, role: "manager" as const },
      { ...actor, issued_role: "cashier" as const },
      { ...actor, session_kind: "sync" as const },
    ])
      await expect(webPayroll(db, a, url)).rejects.toThrow();
    await expect(
      webPayroll(
        db,
        actor,
        new URL(
          "https://fixture.test/web/payroll?employee_id=u2&month=2026-11",
        ),
      ),
    ).rejects.toThrow();
    expect(sqlite.prepare("SELECT COUNT(*) n FROM audit_logs").get()?.n).toBe(
      0,
    );
    const roster = (await (
      await webPayroll(db, actor, new URL("https://fixture.test/web/payroll"))
    ).json()) as { employees: unknown[] };
    expect(roster.employees.length).toBe(1);
    const data = (await (await webPayroll(db, actor, url)).json()) as {
      rows: unknown[];
    };
    expect(data.rows).toEqual([]);
    expect(
      sqlite
        .prepare(
          "SELECT COUNT(*) n FROM audit_logs WHERE action='PAYROLL_HISTORY_VIEW'",
        )
        .get()?.n,
    ).toBe(1);
    await expect(
      webPayroll(
        db,
        actor,
        new URL("https://fixture.test/web/payroll?employee_id=u1&month=wrong"),
      ),
    ).rejects.toThrow();
  } finally {
    sqlite.close();
  }
});
