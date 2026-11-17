import { describe, it, expect } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import worker from "../src/index";
import type { Env } from "../src/index";

describe("foundation", () => {
  it("applies schema and refuses duplicate device codes", () => {
    const db = new DatabaseSync(":memory:");
    try {
      db.exec(readFileSync("migrations/0001_foundation.sql", "utf8"));
      db.exec(
        "INSERT INTO stores VALUES ('s1','NT-CN01','Chi nhánh 1',1,'2026-11-15'); INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d1','s1','A2','Máy 1','approved','2026-11-15');",
      );
      expect(() =>
        db.exec(
          "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d2','s1','A2','Máy 2','approved','2026-11-15')",
        ),
      ).toThrow();
    } finally {
      db.close();
    }
  });
  it("returns 404 for unknown routes", async () => {
    const response = await worker.fetch(
      new Request("http://localhost/missing"),
      {} as Env,
    );
    expect(response.status).toBe(404);
  });
});
