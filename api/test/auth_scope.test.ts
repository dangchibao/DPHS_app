import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { authenticate } from "../src/auth";
import { checkPermission, sha256 } from "../src/security";
import worker from "../src/index";
import type { Env } from "../src/index";

it("Phiên sync không quản trị được, logout không làm mất quyền gửi hàng đợi đã tạo", async () => {
  const { db, sqlite } = testDatabase();
  const interactive = "a".repeat(64),
    sync = "b".repeat(64),
    now = new Date().toISOString(),
    expires = new Date(Date.now() + 86400000).toISOString();
  try {
    sqlite.exec(`INSERT INTO stores VALUES ('s1','NT-CN01','CN01',1,'${now}');
   INSERT INTO devices(id,store_id,code,name,status,created_at,installation_hash) VALUES ('d1','s1','A2','Máy','approved','${now}','installed');
   INSERT INTO users VALUES ('u1','admin','Chủ','hash','salt',1,0,'${now}');
   INSERT INTO employee_store_assignments VALUES ('a1','s1','u1','owner',1,'${now}');`);
    for (const [id, token, kind] of [
      ["interactive", interactive, "interactive"],
      ["sync", sync, "sync"],
    ]) {
      sqlite
        .prepare("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?)")
        .run(
          id,
          "s1",
          "u1",
          "d1",
          await sha256(token),
          now,
          expires,
          0,
          "installed",
          kind,
          "owner",
        );
    }
    const env = {
      DB: db,
      ENVIRONMENT: "development",
      ALLOWED_ORIGIN: "",
    } as Env;
    const syncRequest = new Request("http://localhost/staff", {
      headers: { Authorization: `Bearer ${sync}` },
    });
    expect((await worker.fetch(syncRequest, env)).status).toBe(403);
    expect(
      (
        await worker.fetch(
          new Request("http://localhost/sync/pull?cursor=0", {
            headers: {
              Authorization: `Bearer ${sync}`,
              "X-Client-Schema": "22",
            },
          }),
          env,
        )
      ).status,
    ).toBe(403);
    expect(
      (await authenticate(syncRequest, env, undefined, "sync")).user_id,
    ).toBe("u1");
    const logout = await worker.fetch(
      new Request("http://localhost/auth/logout", {
        method: "POST",
        headers: { Authorization: `Bearer ${interactive}` },
        body: "{}",
      }),
      env,
    );
    expect(logout.status).toBe(200);
    await expect(
      authenticate(
        new Request("http://localhost/auth/me", {
          headers: { Authorization: `Bearer ${interactive}` },
        }),
        env,
      ),
    ).rejects.toThrow();
    expect(
      (await authenticate(syncRequest, env, undefined, "sync")).user_id,
    ).toBe("u1");
    sqlite.exec("UPDATE devices SET status='revoked' WHERE id='d1'");
    await expect(
      authenticate(syncRequest, env, undefined, "sync"),
    ).rejects.toThrow();
  } finally {
    sqlite.close();
  }
});
it("Quyền phiên cũ không tự tăng sau khi được nâng vai trò", () => {
  expect(() => checkPermission("owner", "catalog", "cashier")).toThrow();
  expect(() => checkPermission("owner", "sell", "cashier")).not.toThrow();
});
