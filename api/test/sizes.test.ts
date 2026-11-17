import { it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { sizeBands, suggestSizes } from "../src/sizes";
import { testDatabase } from "./database";
import { push } from "../src/sync";
import type { Actor } from "../src/auth";

const vectors = JSON.parse(
  readFileSync("../docs/test-vectors/size-suggestions.json", "utf8"),
) as {
  rows: unknown;
  cases: { name: string; height: number; weight: number; expected: string[] }[];
};
const bands = sizeBands(vectors.rows);
for (const c of vectors.cases)
  it(c.name, () =>
    expect(suggestSizes(bands, c.height, c.weight)).toEqual(c.expected),
  );
it("Chặn khoảng đảo, số lẻ, cột lạ, size lặp và số đo thiếu", () => {
  for (const value of [
    [],
    [{ ...bands[0], height_min: 1500 }],
    [{ ...bands[0], weight_min: 18.5 }],
    [{ ...bands[0], height: 1300 }],
    [bands[0], bands[0]],
  ])
    expect(() => sizeBands(value)).toThrow();
  expect(() => suggestSizes(bands, 0, 30000)).toThrow();
});
it("API kiểm quyền, cấu hình và LWW bảng size; không ảnh hưởng kho", async () => {
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
    const row = {
      id: "rule",
      store_id: "s1",
      product_id: null,
      name: "Bảng áo",
      config_json: JSON.stringify(bands),
      active: 1,
      updated_at: now,
      lww_key: `${now}|d1|a`,
    };
    const send = (id: string, r = row, a = actor) =>
      push(d.db, a, {
        mutations: [{ id, records: [{ table: "size_rules", row: r }] }],
      });
    await expect(
      send("denied", row, { ...actor, role: "cashier" }),
    ).rejects.toThrow();
    await send("new");
    await send("late", { ...row, name: "Bản cũ", lww_key: `${now}|d1|0` });
    expect(d.sqlite.prepare("SELECT name FROM size_rules").get()?.name).toBe(
      "Bảng áo",
    );
    await expect(send("bad", { ...row, config_json: "[]" })).rejects.toThrow();
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM stock_movements").get()?.n,
    ).toBe(0);
  } finally {
    d.sqlite.close();
  }
});
