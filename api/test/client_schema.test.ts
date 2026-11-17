import { expect, it } from "vitest";
import worker, { type Env } from "../src/index";
import { minimumSyncSchema } from "../src/config";

it("Chặn client cũ trước khi đọc DB, không cho header phiên bản thay quyền", async () => {
  for (const path of ["/directory", "/sync/push", "/sync/pull"]) {
    for (const schema of [undefined, "18", "NaN", "21.5"]) {
      const response = await worker.fetch(
        new Request(`http://localhost${path}`, {
          headers: schema === undefined ? {} : { "X-Client-Schema": schema },
        }),
        {} as Env,
      );
      expect(response.status).toBe(401);
      expect(((await response.json()) as { code: string }).code).toBe(
        "CLIENT_UPGRADE_REQUIRED",
      );
    }
    const response = await worker.fetch(
      new Request(`http://localhost${path}`, {
        method: path === "/sync/push" ? "POST" : "GET",
        headers: { "X-Client-Schema": String(minimumSyncSchema) },
      }),
      {} as Env,
    );
    expect(response.status).toBe(401);
    expect(((await response.json()) as { code: string }).code).not.toBe(
      "CLIENT_UPGRADE_REQUIRED",
    );
  }
});

it("Cho Web gửi header tương thích qua CORS", async () => {
  const response = await worker.fetch(
    new Request("https://api.invalid/sync/pull", {
      method: "OPTIONS",
      headers: { Origin: "https://app.invalid" },
    }),
    { ALLOWED_ORIGIN: "https://app.invalid" } as Env,
  );
  expect(response.status).toBe(204);
  expect(response.headers.get("Access-Control-Allow-Headers")).toContain(
    "X-Client-Schema",
  );
});
