import { expect, it } from "vitest";
import { testDatabase } from "./database";
import worker from "../src/index";
import type { Env } from "../src/index";
import { passwordHash } from "../src/security";

it("KDF ở client; API giữ hash lớp ngoài, từ chối replay hash DB và đổi mật khẩu đúng quyền", async () => {
  const { db, sqlite } = testDatabase();
  const proof = "a".repeat(64),
    salt = "b".repeat(64),
    now = new Date().toISOString();
  const stored = await passwordHash(proof, salt);
  sqlite.exec(`INSERT INTO stores VALUES ('s1','NT-CN01','CN01',1,'${now}');
    INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d1','s1','A2','Máy','approved','${now}');`);
  sqlite
    .prepare("INSERT INTO users VALUES (?,?,?,?,?,?,?,?)")
    .run("u1", "admin", "Chủ", stored, salt, 1, 0, now);
  sqlite
    .prepare("INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?)")
    .run("a1", "s1", "u1", "owner", 1, now);
  const env = {
    DB: db,
    ENVIRONMENT: "production",
    ALLOWED_ORIGIN: "",
    SESSION_SECRET: "test-only-secret-not-for-production-32",
  } as Env;
  const send = (path: string, body: unknown, token?: string) =>
    worker.fetch(
      new Request(`https://test${path}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Client-Schema": "30",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(body),
      }),
      env,
    );
  try {
    const challenge = (await (
      await send("/auth/challenge", { username: "admin" })
    ).json()) as { salt: string; iterations: number };
    expect(challenge).toMatchObject({ salt, iterations: 600000 });
    const login = {
      username: "admin",
      credential: proof,
      store_id: "s1",
      device_id: "d1",
      installation_id: "installation-test-123456",
    };
    expect(
      (await send("/auth/login", { ...login, credential: stored })).status,
    ).toBe(400);
    expect(
      (await send("/auth/login", { ...login, credential: "c".repeat(64) }))
        .status,
    ).toBe(401);
    const response = await send("/auth/login", login);
    expect(response.status).toBe(200);
    const auth = (await response.json()) as {
      token: string;
      sync_token: string;
    };
    expect(
      (
        await send(
          "/auth/password",
          { old_credential: "c".repeat(64), salt, credential: "d".repeat(64) },
          auth.token,
        )
      ).status,
    ).toBe(400);
    expect(
      (
        await send(
          "/auth/password",
          {
            old_credential: proof,
            salt: "e".repeat(64),
            credential: "d".repeat(64),
          },
          auth.token,
        )
      ).status,
    ).toBe(200);
    expect((await send("/auth/login", login)).status).toBe(401);
    expect(
      (await send("/auth/login", { ...login, credential: "d".repeat(64) }))
        .status,
    ).toBe(200);
    expect(
      String(
        sqlite.prepare("SELECT password_hash FROM users").get()?.password_hash,
      ),
    ).toMatch(/^client-v1:[a-f0-9]{64}$/);
    expect(
      (
        await worker.fetch(
          new Request("https://test/sync/pull", {
            headers: { Authorization: `Bearer ${auth.sync_token}` },
          }),
          env,
        )
      ).status,
    ).toBe(401);
  } finally {
    sqlite.close();
  }
});
