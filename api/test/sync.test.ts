import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { testDatabase } from "./database";
import { push, pull } from "../src/sync";
import type { Actor } from "../src/auth";

describe("Đồng bộ lõi", () => {
  let database: ReturnType<typeof testDatabase>;
  const actor: Actor = {
    user_id: "u1",
    store_id: "s1",
    device_id: "d1",
    role: "owner",
    name: "Chủ",
    session_id: "session",
  };
  beforeEach(() => {
    database = testDatabase();
    database.sqlite
      .exec(`INSERT INTO stores VALUES ('s1','NT-CN01','CN01',1,'2026-11-15');
  INSERT INTO stores VALUES ('s2','NT-CN02','CN02',1,'2026-11-15');
  INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d1','s1','A2','Máy 1','approved','2026-11-15');
  INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d2','s1','B2','Máy 2','approved','2026-11-15');
  INSERT INTO users VALUES ('u1','admin','Chủ','hash','salt',1,0,'2026-11-15');
  INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES ('p1','Áo','Áo sơ mi','Unisex','Tiểu học','2026–2027','2026-11-15');
  INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES ('v1','p1','SKU1','M','Trắng','cái',50000,100000,'2026-11-15');`);
  });
  afterEach(() => database.sqlite.close());
  function movement(id: string, quantity: number, device = "d1") {
    return {
      table: "stock_movements",
      row: {
        id,
        store_id: "s1",
        device_id: device,
        variant_id: "v1",
        quantity,
        kind: "adjustment",
        document_id: null,
        reason: "Kiểm kho",
        user_id: "u1",
        created_at: "2026-11-15T00:00:00.000Z",
      },
    };
  }
  it("Gửi lặp không nhân đôi tồn, feed hoặc mutation", async () => {
    const body = { mutations: [{ id: "job1", records: [movement("m1", 10)] }] };
    await push(database.db, actor, body);
    await push(database.db, actor, body);
    expect(
      database.sqlite.prepare("SELECT quantity FROM stock_balances").get()
        ?.quantity,
    ).toBe(10);
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM change_feed").get()?.n,
    ).toBe(1);
  });
  it("Cùng ID thay nội dung bị từ chối", async () => {
    await push(database.db, actor, {
      mutations: [{ id: "job1", records: [movement("m1", 10)] }],
    });
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "job1", records: [movement("m1", 11)] }],
      }),
    ).rejects.toThrow("ID đã dùng");
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "job2", records: [movement("m1", 11)] }],
      }),
    ).rejects.toThrow("bất biến");
  });
  it("Không cho mượn tồn offline của thiết bị khác", async () => {
    await push(database.db, actor, {
      mutations: [{ id: "job1", records: [movement("m1", 10)] }],
    });
    await expect(
      push(
        database.db,
        { ...actor, device_id: "d2" },
        { mutations: [{ id: "job2", records: [movement("m2", -1, "d2")] }] },
      ),
    ).rejects.toThrow("INSUFFICIENT_DEVICE_ALLOCATION");
    expect(
      database.sqlite.prepare("SELECT quantity FROM stock_balances").get()
        ?.quantity,
    ).toBe(10);
  });
  it("Rollback cả bundle khi một dòng lỗi FK", async () => {
    const invalid = movement("m2", 2);
    invalid.row.variant_id = "missing";
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "job1", records: [movement("m1", 10), invalid] }],
      }),
    ).rejects.toThrow();
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM stock_movements").get()
        ?.n,
    ).toBe(0);
    expect(
      database.sqlite
        .prepare("SELECT COUNT(*) AS n FROM processed_mutations")
        .get()?.n,
    ).toBe(0);
  });
  it("Pull theo cursor và phạm vi cửa hàng", async () => {
    await push(database.db, actor, {
      mutations: [{ id: "job1", records: [movement("m1", 10)] }],
    });
    const first = (await (
      await pull(
        database.db,
        actor,
        new URL("http://localhost/sync/pull?cursor=0"),
      )
    ).json()) as { events: unknown[]; cursor: number };
    expect(first.events).toHaveLength(1);
    const again = (await (
      await pull(
        database.db,
        actor,
        new URL(`http://localhost/sync/pull?cursor=${first.cursor}`),
      )
    ).json()) as { events: unknown[] };
    expect(again.events).toHaveLength(0);
    const other = (await (
      await pull(
        database.db,
        { ...actor, store_id: "s2" },
        new URL("http://localhost/sync/pull?cursor=0"),
      )
    ).json()) as { events: unknown[] };
    expect(other.events).toHaveLength(0);
  });
  it("API không chấp nhận giả cửa hàng hoặc nhập kho bằng tài khoản thu ngân", async () => {
    await expect(
      push(
        database.db,
        { ...actor, role: "cashier" },
        { mutations: [{ id: "j1", records: [movement("m1", 1)] }] },
      ),
    ).rejects.toThrow("quyền");
    const foreign = movement("m1", 1);
    foreign.row.store_id = "s2";
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "j1", records: [foreign] }],
      }),
    ).rejects.toThrow("cửa hàng");
  });
  it("LWW đồng nhất dù bản cũ đến sau; feed chứa bản thắng", async () => {
    const base = database.sqlite.prepare("SELECT * FROM products").get()!;
    const newer = {
      ...base,
      name: "Áo mới",
      updated_at: "2026-11-15T01:00:00.000Z",
      lww_key: "2026-11-15T01:00:00.000Z|d1|j1",
    };
    const older = {
      ...base,
      name: "Áo cũ",
      updated_at: "2026-11-14T01:00:00.000Z",
      lww_key: "2026-11-14T01:00:00.000Z|d2|j2",
    };
    await push(database.db, actor, {
      mutations: [{ id: "j1", records: [{ table: "products", row: newer }] }],
    });
    await push(database.db, actor, {
      mutations: [{ id: "j2", records: [{ table: "products", row: older }] }],
    });
    expect(
      database.sqlite.prepare("SELECT name FROM products").get()?.name,
    ).toBe("Áo mới");
    const feed = database.sqlite
      .prepare(
        "SELECT payload FROM change_feed ORDER BY server_seq DESC LIMIT 1",
      )
      .get()!;
    expect(JSON.parse(feed.payload as string).name).toBe("Áo mới");
  });
});
