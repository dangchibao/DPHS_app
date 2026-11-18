import { it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
it("Mọi migration D1 giống bản Drift và chạy cùng nhau", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const files = readdirSync("migrations")
      .filter((f) => f.endsWith(".sql"))
      .sort();
    for (const file of files) {
      const sql = readFileSync(`migrations/${file}`, "utf8");
      expect(readFileSync(`../app/assets/migrations/${file}`, "utf8")).toBe(
        sql,
      );
      db.exec(sql);
    }
    expect(
      db.prepare("SELECT MAX(version) AS version FROM schema_metadata").get()
        ?.version,
    ).toBe(30);
  } finally {
    db.close();
  }
});
