import { beforeEach, afterEach, it, expect } from "vitest";
import { testDatabase } from "./database";
import { push, type SyncRecord } from "../src/sync";
import type { Actor } from "../src/auth";

let database: ReturnType<typeof testDatabase>;
const actor: Actor = {
  user_id: "u1",
  store_id: "s1",
  device_id: "d1",
  role: "owner",
  name: "Chủ",
  session_id: "session",
};
const now = new Date().toISOString(),
  day = new Date(Date.now() + 7 * 3600000)
    .toISOString()
    .slice(0, 10)
    .replaceAll("-", "");
const version = `${now}|d1|combo`;
beforeEach(() => {
  database = testDatabase();
  database.sqlite
    .exec(`INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'${now}');
    INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','${now}');
    INSERT INTO users VALUES('u1','admin','Chủ','hash','salt',1,0,'${now}');
    INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES('p1','Áo','Áo sơ mi','Unisex','Tiểu học','2026–2027','${now}');
    INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at,lww_key) VALUES('v1','p1','SKU-M','M','Trắng','cái',20000,100000,'${now}','price-v1');
    INSERT INTO stock_movements VALUES('initial','s1','d1','v1',10,'receipt',NULL,'Nhập','u1','${now}');`);
});
afterEach(() => database.sqlite.close());
function rule(price = 50001, time = now, key = version): SyncRecord {
  return {
    table: "combo_rules",
    row: {
      id: "combo",
      store_id: "s1",
      name: "Hai áo",
      price,
      items_json: JSON.stringify([{ product_id: "p1", quantity: 2 }]),
      active: 1,
      updated_at: time,
      lww_key: key,
    },
  };
}
function sale(
  id: string,
  sequence: number,
  price = 50001,
  proofVersion = version,
): SyncRecord[] {
  const unit = Math.ceil(price / 2),
    gross = unit * 2,
    rounding = gross - price;
  return [
    {
      table: "documents",
      row: {
        id,
        store_id: "s1",
        device_id: "d1",
        type: "HD",
        kind: "sale",
        code: `HD-CN01-A2-${day}-${String(sequence).padStart(3, "0")}`,
        issued_at: now,
        user_id: "u1",
        customer_id: null,
        original_id: null,
        subtotal: gross,
        discount: rounding,
        total: price,
        school_year: "2026–2027",
        metadata_json: JSON.stringify({
          manual_discount: 0,
          regular_subtotal: 200000,
          combo_groups: [
            {
              rule_id: "combo",
              version: proofVersion,
              picks: ["v1"],
              quantity: 1,
            },
          ],
        }),
      },
    },
    {
      table: "invoice_lines",
      row: {
        id: `line-${id}`,
        store_id: "s1",
        document_id: id,
        variant_id: "v1",
        name: "Áo",
        size: "M",
        color: "Trắng",
        unit: "cái",
        quantity: 2,
        unit_price: unit,
        unit_cost: 20000,
        discount: rounding,
        price_version: "price-v1",
      },
    },
    {
      table: "payments",
      row: {
        id: `pay-${id}`,
        store_id: "s1",
        device_id: "d1",
        document_id: id,
        user_id: "u1",
        amount: price,
        method: "cash",
        direction: "receive",
        created_at: now,
        note: "",
      },
    },
    {
      table: "stock_movements",
      row: {
        id: `stock-${id}`,
        store_id: "s1",
        device_id: "d1",
        variant_id: "v1",
        quantity: -2,
        kind: "sale",
        document_id: id,
        reason: "Bán combo",
        user_id: "u1",
        created_at: now,
      },
    },
  ];
}
it("Thu ngân bán đúng giá combo đã cấu hình, trừ từng món; replay không nhân đôi", async () => {
  await push(database.db, actor, {
    mutations: [{ id: "rule", records: [rule()] }],
  });
  const body = { mutations: [{ id: "sale", records: sale("invoice", 1) }] };
  await push(database.db, { ...actor, role: "cashier" }, body);
  await push(database.db, { ...actor, role: "cashier" }, body);
  expect(
    database.sqlite.prepare("SELECT quantity FROM stock_balances").get()
      ?.quantity,
  ).toBe(8);
  expect(
    database.sqlite.prepare("SELECT total,discount FROM documents").get(),
  ).toMatchObject({ total: 50001, discount: 1 });
  await expect(
    push(
      database.db,
      { ...actor, role: "cashier" },
      { mutations: [{ id: "bad-sale", records: sale("forged", 2, 1) }] },
    ),
  ).rejects.toThrow("phiên bản giá");
  expect(
    database.sqlite.prepare("SELECT COUNT(*) AS n FROM documents").get()?.n,
  ).toBe(1);
});
it("Giữ phiên bản combo thua LWW cho hóa đơn offline; không cho thay nội dung cùng phiên bản", async () => {
  await push(database.db, actor, {
    mutations: [{ id: "current-rule", records: [rule()] }],
  });
  const oldTime = new Date(Date.now() - 60000).toISOString(),
    oldVersion = `${oldTime}|d1|old`;
  await push(database.db, actor, {
    mutations: [
      { id: "old-rule", records: [rule(200001, oldTime, oldVersion)] },
    ],
  });
  expect(
    database.sqlite.prepare("SELECT price FROM combo_rules").get()?.price,
  ).toBe(50001);
  await push(database.db, actor, {
    mutations: [
      { id: "old-sale", records: sale("old-invoice", 1, 200001, oldVersion) },
    ],
  });
  expect(
    database.sqlite.prepare("SELECT total FROM documents").get()?.total,
  ).toBe(200001);
  await expect(
    push(database.db, actor, {
      mutations: [
        { id: "version-forgery", records: [rule(1, oldTime, oldVersion)] },
      ],
    }),
  ).rejects.toThrow("COMBO_VERSION_CONFLICT");
});
it("Thu ngân không sửa combo; API không nhận thành phần không tồn tại", async () => {
  await expect(
    push(
      database.db,
      { ...actor, role: "cashier" },
      { mutations: [{ id: "cashier-rule", records: [rule()] }] },
    ),
  ).rejects.toThrow("quyền");
  const bad = rule();
  bad.row.items_json = JSON.stringify([{ product_id: "missing", quantity: 1 }]);
  await expect(
    push(database.db, actor, {
      mutations: [{ id: "missing-part", records: [bad] }],
    }),
  ).rejects.toThrow("không tồn tại");
  expect(
    database.sqlite.prepare("SELECT COUNT(*) AS n FROM combo_rules").get()?.n,
  ).toBe(0);
});
