import { DatabaseSync } from "node:sqlite";
import { readFileSync, readdirSync } from "node:fs";

export function testDatabase() {
  const sqlite = new DatabaseSync(":memory:");
  for (const file of readdirSync("migrations")
    .filter((f) => f.endsWith(".sql"))
    .sort())
    sqlite.exec(readFileSync(`migrations/${file}`, "utf8"));
  const wrap = (sql: string, parameters: unknown[] = []) => ({
    bind: (...values: unknown[]) => wrap(sql, values),
    first: async () =>
      sqlite.prepare(sql).get(...(parameters as (string | number | null)[])) ??
      null,
    all: async () => ({
      results: sqlite
        .prepare(sql)
        .all(...(parameters as (string | number | null)[])),
      success: true,
      meta: {},
    }),
    run: async () => ({
      success: true,
      meta: sqlite
        .prepare(sql)
        .run(...(parameters as (string | number | null)[])),
    }),
    _run: () => {
      const stmt = sqlite.prepare(sql);
      return stmt.columns().length
        ? stmt.all(...(parameters as (string | number | null)[]))
        : stmt.run(...(parameters as (string | number | null)[]));
    },
  });
  const db = {
    prepare: (sql: string) => wrap(sql),
    batch: async (statements: ReturnType<typeof wrap>[]) => {
      sqlite.exec("BEGIN");
      try {
        const results = statements.map((stmt) => ({
          success: true,
          results: stmt._run(),
          meta: {},
        }));
        sqlite.exec("COMMIT");
        return results;
      } catch (e) {
        sqlite.exec("ROLLBACK");
        throw e;
      }
    },
  } as unknown as D1Database;
  return { sqlite, db };
}
