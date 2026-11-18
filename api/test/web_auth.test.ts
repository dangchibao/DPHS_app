import { expect, it } from "vitest";
import { testDatabase } from "./database";
import worker, { type Env } from "../src/index";
import { passwordHash } from "../src/security";
import { management, enrollDevice } from "../src/management";

async function fixture() {
  const { db, sqlite } = testDatabase(),
    proof = "a".repeat(64),
    salt = "b".repeat(64),
    now = new Date().toISOString();
  sqlite.exec(
    `INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'${now}'); INSERT INTO devices(id,store_id,code,name,status,created_at,kind) VALUES('d1','s1','A2','Máy','approved','${now}','native'),('w1','s1','W1','Web','approved','${now}','web');`,
  );
  sqlite
    .prepare("INSERT INTO users VALUES(?,?,?,?,?,?,?,?)")
    .run(
      "u1",
      "admin",
      "Chủ",
      await passwordHash(proof, salt),
      salt,
      1,
      0,
      now,
    );
  sqlite
    .prepare("INSERT INTO employee_store_assignments VALUES(?,?,?,?,?,?)")
    .run("a1", "s1", "u1", "owner", 1, now);
  const env = {
    DB: db,
    ENVIRONMENT: "production",
    ALLOWED_ORIGIN: "https://web.test",
    SESSION_SECRET: "fixture-only-secret-32-characters-min",
  } as Env;
  const send = (path: string, body?: unknown, token?: string) =>
    worker.fetch(
      new Request(`https://api.test${path}`, {
        method: body === undefined ? "GET" : "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Client-Schema": "30",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
      env,
    );
  const login = {
    username: "admin",
    credential: proof,
    store_id: "s1",
    device_id: "w1",
    installation_id: "web-installation-fixture-123",
  };
  return { db, sqlite, send, login };
}
it("Web không nhận sync token, không giả máy native hoặc truy cập ledger; role/revoke áp dụng từ server", async () => {
  const { sqlite, send, login } = await fixture();
  try {
    expect((await send("/auth/login", login)).status).toBe(401);
    expect(
      (await send("/auth/web/login", { ...login, device_id: "d1" })).status,
    ).toBe(401);
    const response = await send("/auth/web/login", login);
    expect(response.status).toBe(200);
    const auth = (await response.json()) as {
      token: string;
      expires_at: string;
      sync_token?: string;
    };
    expect(auth.sync_token).toBeUndefined();
    expect(Date.parse(auth.expires_at) - Date.now()).toBeLessThanOrEqual(
      8 * 3600000,
    );
    expect(
      sqlite
        .prepare("SELECT COUNT(*) AS n FROM sessions WHERE device_id='w1'")
        .get()?.n,
    ).toBe(1);
    expect((await send("/reports/options", undefined, auth.token)).status).toBe(
      200,
    );
    expect((await send("/staff", undefined, auth.token)).status).toBe(200);
    const exportBody = {
      id: "019a1234-0000-7000-8000-000000000099",
      name: "Doanh thu CN01",
      format: "XLSX",
    };
    expect((await send("/reports/export", exportBody, auth.token)).status).toBe(
      200,
    );
    expect((await send("/reports/export", exportBody, auth.token)).status).toBe(
      200,
    );
    expect(
      sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM audit_logs WHERE action='REPORT_EXPORT_REQUEST'",
        )
        .get()?.n,
    ).toBe(1);
    expect(
      (
        await send(
          "/reports/export",
          { ...exportBody, format: "PDF" },
          auth.token,
        )
      ).status,
    ).toBe(409);
    for (const [path, body] of [
      ["/sync/push", { mutations: [] }],
      ["/payroll/push", {}],
      ["/sync/pull", undefined],
      ["/directory", undefined],
      ["/sync/checkpoint", {}],
    ] as const)
      expect((await send(path, body, auth.token)).status).toBe(403);
    expect(
      (
        await send("/auth/web/login", {
          ...login,
          installation_id: "different-web-installation",
        })
      ).status,
    ).toBe(409);
    sqlite.exec(
      "UPDATE employee_store_assignments SET role='cashier' WHERE user_id='u1'",
    );
    expect((await send("/reports/options", undefined, auth.token)).status).toBe(
      403,
    );
    expect((await send("/reports/export", exportBody, auth.token)).status).toBe(
      403,
    );
    sqlite.exec("UPDATE devices SET status='revoked' WHERE id='w1'");
    expect((await send("/auth/me", undefined, auth.token)).status).toBe(401);
  } finally {
    sqlite.close();
  }
});
it("Loại Web bất biến; ledger không cấp tồn cho Web; Web không là đích chuyển kho hoặc máy phải chốt lương", async () => {
  const { sqlite, db } = await fixture();
  try {
    expect(() =>
      sqlite.exec("UPDATE devices SET kind='native' WHERE id='w1'"),
    ).toThrow(/DEVICE_IDENTITY/);
    expect(() =>
      sqlite.exec(
        "INSERT INTO device_stock_allocations VALUES('s1','w1','v1',1)",
      ),
    ).toThrow(/WEB_STOCK_FORBIDDEN/);
    expect(() =>
      sqlite.exec(
        "INSERT INTO stock_movements VALUES('m1','s1','w1','v1',1,'receipt',NULL,'Nhập','u1','2026-11-17')",
      ),
    ).toThrow(/WEB_STOCK_FORBIDDEN/);
    const actor = {
      user_id: "u1",
      store_id: "s1",
      device_id: "d1",
      role: "owner" as const,
      name: "Chủ",
      session_id: "fixture",
    };
    const invite = await management(db, actor, {
      action: "invite_device",
      id: "019a1234-0000-7000-8000-000000000001",
      enrollment_id: "019a1234-0000-7000-8000-000000000002",
      store_id: "s1",
      code: "W2",
      name: "iPad",
      kind: "web",
      reason: "Đăng ký quản lý",
    });
    const data = (await invite.json()) as { token: string; device_id: string };
    await expect(
      enrollDevice(db, {
        token: data.token,
        installation_id: "wrong-native-fixture-installation",
      }),
    ).rejects.toThrow(/loại thiết bị/);
    expect(
      sqlite
        .prepare("SELECT installation_hash FROM devices WHERE id=?")
        .get(data.device_id)?.installation_hash,
    ).toBeNull();
    const enrolled = await enrollDevice(db, {
      token: data.token,
      kind: "web",
      installation_id: "browser-fixture-installation-2",
    });
    expect(
      ((await enrolled.json()) as { device: { kind: string; status: string } })
        .device,
    ).toMatchObject({ kind: "web", status: "pending" });
    await management(db, actor, {
      action: "set_device",
      store_id: "s1",
      id: data.device_id,
      status: "approved",
      reason: "Đã kiểm tra",
    });
    expect(
      sqlite
        .prepare("SELECT kind,status FROM devices WHERE id=?")
        .get(data.device_id),
    ).toMatchObject({ kind: "web", status: "approved" });
  } finally {
    sqlite.close();
  }
});
