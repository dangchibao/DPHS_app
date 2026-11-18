import { it, expect } from "vitest";
import { fixture, actor } from "./report_fixtures";
import { staff, authenticate } from "../src/auth";
import { directory } from "../src/directory";
import { handoffRequests, handoffAck } from "../src/staff_handoffs";
import { management } from "../src/management";
import { sha256 } from "../src/security";
import type { Env } from "../src/index";
const id = "019a1234-0000-7000-8000-000000000070";
const change = {
  id: "u2",
  username: "staff",
  display_name: "Nhân viên",
  role: "warehouse",
  active: true,
  reason: "Bàn giao vị trí",
  change_id: id,
};
function setup() {
  const f = fixture();
  f.sqlite.exec(
    "INSERT INTO employee_store_assignments VALUES('a1','s1','u1','owner',1,'2026-11-15'),('a2','s1','u2','cashier',1,'2026-11-15'); INSERT INTO devices(id,store_id,code,name,status,created_at,kind) VALUES('d2','s1','B2','Máy offline','approved','2026-11-15','native'),('w1','s1','W1','Web','approved','2026-11-15','web');",
  );
  return { ...f, env: { DB: f.db } as Env };
}
async function ack(db: D1Database, device: string, store = "s1") {
  const cursor = (await db
    .prepare(
      "SELECT COALESCE(MAX(server_seq),0) AS seq FROM change_feed WHERE store_id=?",
    )
    .bind(store)
    .first<{ seq: number }>())!.seq;
  return handoffAck(
    db,
    { ...actor, device_id: device, store_id: store, device_kind: "native" },
    { id, drained: true, cursor },
  );
}
it("Chờ đủ native ACK, từ chối cursor/ACK giả, đổi quyền nguyên tử và replay không ghi lại", async () => {
  const f = setup();
  try {
    const prepared = await staff(f.env, actor, change);
    expect(prepared.status).toBe(202);
    expect(
      f.sqlite.prepare("SELECT COUNT(*) AS n FROM staff_change_devices").get()
        ?.n,
    ).toBe(2);
    expect(
      f.sqlite
        .prepare(
          "SELECT role FROM employee_store_assignments WHERE user_id='u2'",
        )
        .get()?.role,
    ).toBe("cashier");
    const commit = () =>
      staff(f.env, actor, { ...change, change_request: id, confirmed: true });
    await expect(commit()).rejects.toThrow(/Còn máy/);
    await expect(
      handoffAck(
        f.db,
        { ...actor, device_kind: "web" },
        { id, drained: true, cursor: 0 },
      ),
    ).rejects.toThrow();
    await expect(
      handoffAck(f.db, actor, { id, drained: false, cursor: 0 }),
    ).rejects.toThrow();
    await expect(
      handoffAck(f.db, actor, { id, drained: true, cursor: 9999 }),
    ).rejects.toThrow(/staff_handoff_valid/);
    await ack(f.db, "d1");
    await expect(commit()).rejects.toThrow(/Còn máy/);
    await ack(f.db, "d2");
    await commit();
    expect(
      f.sqlite
        .prepare(
          "SELECT role FROM employee_store_assignments WHERE user_id='u2'",
        )
        .get()?.role,
    ).toBe("warehouse");
    expect(
      f.sqlite.prepare("SELECT status FROM staff_change_requests").get()
        ?.status,
    ).toBe("completed");
    const before = f.sqlite
      .prepare("SELECT COUNT(*) AS n FROM audit_logs")
      .get()?.n;
    await commit();
    expect(
      f.sqlite.prepare("SELECT COUNT(*) AS n FROM audit_logs").get()?.n,
    ).toBe(before);
  } finally {
    f.sqlite.close();
  }
});
it("Freeze chặn tương tác nhưng giữ sync cũ; directory báo khóa; hủy không đổi quyền", async () => {
  const f = setup();
  try {
    f.sqlite.exec(
      "UPDATE devices SET installation_hash='installed' WHERE id='d1'",
    );
    for (const [kind, token] of [
      ["interactive", "a".repeat(64)],
      ["sync", "b".repeat(64)],
    ])
      await f.db
        .prepare("INSERT INTO sessions VALUES(?,?,?,?,?,?,?,?,?,?,?)")
        .bind(
          kind,
          "s1",
          "u2",
          "d1",
          await sha256(token),
          "2026-11-17",
          "2027-11-17",
          0,
          "installed",
          kind,
          "cashier",
        )
        .run();
    await staff(f.env, actor, change);
    const request = (path: string, token = "a".repeat(64)) =>
      new Request("https://fixture" + path, {
        headers: { Authorization: `Bearer ${token}` },
      });
    await expect(
      authenticate(request("/auth/me"), f.env),
    ).rejects.toMatchObject({ code: "STAFF_HANDOFF_PENDING" });
    const frozen = await authenticate(request("/directory"), f.env);
    expect(frozen.frozen).toBe(1);
    expect(
      (
        await authenticate(
          request("/sync/push", "b".repeat(64)),
          f.env,
          undefined,
          "sync",
        )
      ).user_id,
    ).toBe("u2");
    await expect(
      authenticate(request("/sync/pull?scope=audit"), f.env),
    ).rejects.toMatchObject({ code: "STAFF_HANDOFF_PENDING" });
    const data = (await (await directory(f.db, frozen)).json()) as {
      users: { id: string; frozen: number }[];
      handoffs: { id: string }[];
    };
    expect(data.users.find((u) => u.id === "u2")?.frozen).toBe(1);
    expect(data.handoffs[0].id).toBe(id);
    await handoffRequests(f.db, actor, {
      id,
      action: "cancel",
      reason: "Cần đăng nhập lại để gửi queue",
    });
    await expect(
      authenticate(request("/auth/me"), f.env),
    ).rejects.toMatchObject({ status: 401 });
    expect(
      (
        await authenticate(
          request("/sync/push", "b".repeat(64)),
          f.env,
          undefined,
          "sync",
        )
      ).frozen,
    ).toBe(0);
    expect(
      f.sqlite
        .prepare(
          "SELECT role FROM employee_store_assignments WHERE user_id='u2'",
        )
        .get()?.role,
    ).toBe("cashier");
  } finally {
    f.sqlite.close();
  }
});
it("Khóa toàn user chờ các chi nhánh; role mới chưa tái xác thực không được nâng quyền chủ", async () => {
  const f = setup();
  try {
    f.sqlite.exec(
      "INSERT INTO stores VALUES('s2','NT-CN02','CN02',1,'2026-11-15'); INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d3','s2','C3','Máy CN02','approved','2026-11-15'); INSERT INTO employee_store_assignments VALUES('a3','s2','u2','cashier',1,'2026-11-15');",
    );
    await expect(
      staff(
        f.env,
        { ...actor, issued_role: "manager" },
        { ...change, role: "owner" },
      ),
    ).rejects.toThrow();
    await staff(f.env, actor, { ...change, role: "cashier", active: false });
    expect(
      f.sqlite.prepare("SELECT COUNT(*) AS n FROM staff_change_devices").get()
        ?.n,
    ).toBe(3);
    const hidden = (await (
      await handoffRequests(f.db, { ...actor, issued_role: "manager" })
    ).json()) as { requests: unknown[] };
    expect(hidden.requests).toHaveLength(0);
    await ack(f.db, "d1");
    await ack(f.db, "d2");
    await expect(
      staff(f.env, actor, {
        ...change,
        role: "cashier",
        active: false,
        change_request: id,
        confirmed: true,
      }),
    ).rejects.toThrow(/Còn máy/);
    await ack(f.db, "d3", "s2");
    await staff(f.env, actor, {
      ...change,
      role: "cashier",
      active: false,
      change_request: id,
      confirmed: true,
    });
    expect(
      f.sqlite.prepare("SELECT active FROM users WHERE id='u2'").get()?.active,
    ).toBe(0);
  } finally {
    f.sqlite.close();
  }
});
it("Máy mới được duyệt tham gia fence; race phiên bản rollback cả quyền và trạng thái", async () => {
  const f = setup();
  try {
    await staff(f.env, actor, change);
    await ack(f.db, "d1");
    await ack(f.db, "d2");
    f.sqlite.exec(
      "INSERT INTO devices(id,store_id,code,name,status,created_at,installation_hash) VALUES('d4','s1','D4','Mới','pending','2026-11-17','installed-new')",
    );
    await management(f.db, actor, {
      action: "set_device",
      store_id: "s1",
      id: "d4",
      status: "approved",
      reason: "Bổ sung máy",
    });
    const commit = () =>
      staff(f.env, actor, { ...change, change_request: id, confirmed: true });
    await expect(commit()).rejects.toThrow(/Còn máy/);
    await ack(f.db, "d4");
    const race = {
      ...f.db,
      batch: async (statements: D1PreparedStatement[]) => {
        if (statements.length > 4)
          f.sqlite.exec(
            "UPDATE employee_store_assignments SET role='manager' WHERE store_id='s1' AND user_id='u2'",
          );
        return f.db.batch(statements);
      },
    } as D1Database;
    await expect(
      staff({ ...f.env, DB: race }, actor, {
        ...change,
        change_request: id,
        confirmed: true,
      }),
    ).rejects.toThrow(/staff_handoff_valid/);
    expect(
      f.sqlite.prepare("SELECT status FROM staff_change_requests").get()
        ?.status,
    ).toBe("pending");
    expect(
      f.sqlite
        .prepare(
          "SELECT role FROM employee_store_assignments WHERE user_id='u2'",
        )
        .get()?.role,
    ).toBe("manager");
  } finally {
    f.sqlite.close();
  }
});
it("Đổi tên không thu hồi phiên; đổi vai trò một cửa hàng giữ phiên cửa hàng khác", async () => {
  const f = setup();
  try {
    f.sqlite.exec(
      "INSERT INTO stores VALUES('s2','NT-CN02','CN02',1,'2026-11-15'); INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d3','s2','C3','Máy CN02','approved','2026-11-15'); INSERT INTO employee_store_assignments VALUES('a3','s2','u2','cashier',1,'2026-11-15');",
    );
    f.sqlite.exec(
      "UPDATE devices SET installation_hash='fixture-installation' WHERE id IN('d1','d3')",
    );
    for (const [session, store, device] of [
      ["old-s1", "s1", "d1"],
      ["old-s2", "s2", "d3"],
    ])
      f.sqlite
        .prepare("INSERT INTO sessions VALUES(?,?,?,?,?,?,?,?,?,?,?)")
        .run(
          session,
          store,
          "u2",
          device,
          session,
          "2026",
          "2027",
          0,
          "fixture-installation",
          "sync",
          "cashier",
        );
    await staff(f.env, actor, {
      ...change,
      role: "cashier",
      display_name: "Tên mới",
    });
    expect(
      f.sqlite.prepare("SELECT SUM(revoked) AS n FROM sessions").get()?.n,
    ).toBe(0);
    await staff(f.env, actor, change);
    await ack(f.db, "d1");
    await ack(f.db, "d2");
    await staff(f.env, actor, {
      ...change,
      change_request: id,
      confirmed: true,
    });
    expect(
      f.sqlite.prepare("SELECT revoked FROM sessions WHERE id='old-s1'").get()
        ?.revoked,
    ).toBe(1);
    expect(
      f.sqlite.prepare("SELECT revoked FROM sessions WHERE id='old-s2'").get()
        ?.revoked,
    ).toBe(0);
  } finally {
    f.sqlite.close();
  }
});
