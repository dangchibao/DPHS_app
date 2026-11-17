import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { push, type SyncRecord } from "../src/sync";
import type { Actor } from "../src/auth";
import { validateReservations } from "../src/reservations";

const actor: Actor = {
  user_id: "u1",
  store_id: "s1",
  device_id: "d1",
  role: "owner",
  name: "Chủ",
  session_id: "session",
};
const now = new Date().toISOString(),
  expiry = new Date(Date.parse(now) + 3600000).toISOString(),
  day = new Date(Date.parse(now) + 7 * 3600000)
    .toISOString()
    .slice(0, 10)
    .replaceAll("-", "");
function fixture() {
  const d = testDatabase();
  d.sqlite.exec(`INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'${now}');
    INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','${now}');
    INSERT INTO users VALUES('u1','admin','Chủ','hash','salt',1,0,'${now}');
    INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES('p1','Áo','Áo','Unisex','Tiểu học','2026','${now}');
    INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at,lww_key) VALUES('v1','p1','V1','M','Trắng','cái',50000,100000,'${now}','version1');
    INSERT INTO customers VALUES('c1','s1','Khách','','parent','${now}','customer1');
    INSERT INTO stock_movements VALUES('initial','s1','d1','v1',10,'receipt',NULL,'Nhập','u1','${now}');`);
  return d;
}
function hold(): SyncRecord[] {
  return [
    {
      table: "documents",
      row: {
        id: "dh",
        store_id: "s1",
        device_id: "d1",
        type: "DH",
        kind: "reservation",
        code: `DH-CN01-A2-${day}-001`,
        issued_at: now,
        user_id: "u1",
        customer_id: "c1",
        original_id: null,
        subtotal: 700000,
        discount: 0,
        total: 700000,
        school_year: "2026",
        metadata_json: JSON.stringify({
          expires_at: expiry,
          customer_name: "Khách",
          phone: "",
        }),
      },
    },
    {
      table: "invoice_lines",
      row: {
        id: "line",
        store_id: "s1",
        document_id: "dh",
        variant_id: "v1",
        name: "Áo",
        size: "M",
        color: "Trắng",
        unit: "cái",
        quantity: 7,
        unit_price: 100000,
        unit_cost: 50000,
        discount: 0,
        price_version: "version1",
      },
    },
    {
      table: "reservation_lines",
      row: {
        id: "held",
        store_id: "s1",
        device_id: "d1",
        document_id: "dh",
        variant_id: "v1",
        quantity: 7,
        expires_at: expiry,
        created_at: now,
      },
    },
  ];
}
function release(): SyncRecord {
  return {
    table: "reservation_events",
    row: {
      id: "release",
      store_id: "s1",
      device_id: "d1",
      document_id: "dh",
      kind: "release",
      related_document_id: null,
      user_id: "u1",
      reason: "Khách hủy giữ",
      created_at: now,
    },
  };
}
const send = (db: D1Database, id: string, records: SyncRecord[]) =>
  push(db, actor, { mutations: [{ id, records }] });

it("Giao DH thành HD qua API, rollback khi thiếu consume và không xuất kho hai lần", async () => {
  const d = fixture();
  try {
    await send(d.db, "create", hold());
    const hd: SyncRecord = {
      table: "documents",
      row: {
        ...hold()[0].row,
        id: "hd",
        type: "HD",
        kind: "sale",
        code: `HD-CN01-A2-${day}-001`,
        metadata_json: JSON.stringify({
          reservation_id: "dh",
          manual_discount: 0,
          regular_subtotal: 700000,
          paid: 700000,
          change: 0,
        }),
      },
    };
    const line: SyncRecord = {
      table: "invoice_lines",
      row: { ...hold()[1].row, id: "hd-line", document_id: "hd" },
    };
    const event = release();
    Object.assign(event.row, {
      id: "consume",
      kind: "consume",
      related_document_id: "hd",
    });
    const movement: SyncRecord = {
      table: "stock_movements",
      row: {
        id: "sold",
        store_id: "s1",
        device_id: "d1",
        variant_id: "v1",
        quantity: -7,
        kind: "sale",
        document_id: "hd",
        reason: "Giao hàng",
        user_id: "u1",
        created_at: now,
      },
    };
    const payment: SyncRecord = {
      table: "payments",
      row: {
        id: "pay",
        store_id: "s1",
        device_id: "d1",
        document_id: "hd",
        user_id: "u1",
        amount: 700000,
        method: "cash",
        direction: "receive",
        created_at: now,
        note: "Giao hàng",
      },
    };
    await expect(
      send(d.db, "missing", [hd, line, movement, payment]),
    ).rejects.toThrow("thiếu sự kiện");
    const bundle = [hd, line, event, movement, payment];
    await send(d.db, "fulfilled", bundle);
    await send(d.db, "fulfilled", bundle);
    await send(d.db, "fulfilled-again", bundle);
    expect(
      d.sqlite.prepare("SELECT quantity FROM stock_balances").get()?.quantity,
    ).toBe(3);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM payments").get()?.n,
    ).toBe(1);
  } finally {
    d.sqlite.close();
  }
});

it("DH không xuất kho; bảo vệ phần giữ; release idempotent và xuất feed", async () => {
  const d = fixture();
  try {
    await send(d.db, "create", hold());
    await send(d.db, "create", hold());
    expect(
      d.sqlite.prepare("SELECT quantity FROM stock_balances").get()?.quantity,
    ).toBe(10);
    expect(() =>
      d.sqlite.exec(
        `INSERT INTO stock_movements VALUES('take','s1','d1','v1',-4,'adjustment',NULL,'Xuất','u1','${now}')`,
      ),
    ).toThrow("INSUFFICIENT_AVAILABLE_STOCK");
    await push(
      d.db,
      { ...actor, role: "warehouse", issued_role: "warehouse" },
      { mutations: [{ id: "release", records: [release()] }] },
    );
    await send(d.db, "release-again", [release()]);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM reservation_events").get()?.n,
    ).toBe(1);
    expect(
      d.sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM change_feed WHERE entity_type='reservation_events'",
        )
        .get()?.n,
    ).toBe(2);
    d.sqlite.exec(
      `INSERT INTO stock_movements VALUES('take','s1','d1','v1',-4,'adjustment',NULL,'Xuất','u1','${now}')`,
    );
    expect(
      d.sqlite.prepare("SELECT quantity FROM stock_balances").get()?.quantity,
    ).toBe(6);
  } finally {
    d.sqlite.close();
  }
});
it("Chặn payload giả số lượng, quyền, máy, ngày và thêm dòng DH đã phát hành", async () => {
  const d = fixture();
  try {
    const forged = hold();
    forged[2].row.quantity = 6;
    await expect(send(d.db, "bad", forged)).rejects.toThrow("không khớp");
    await expect(
      push(
        d.db,
        { ...actor, role: "accountant" },
        { mutations: [{ id: "deny", records: hold() }] },
      ),
    ).rejects.toThrow();
    await send(d.db, "good", hold());
    const wrong = release();
    wrong.row.device_id = "d2";
    await expect(send(d.db, "wrong-device", [wrong])).rejects.toThrow(
      "Danh tính",
    );
    const extra = hold();
    extra[1].row.id = "extra-line";
    extra[2].row.id = "extra-hold";
    await expect(send(d.db, "extra", extra)).rejects.toThrow(
      "Không được thêm dòng",
    );
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM reservation_lines").get()?.n,
    ).toBe(1);
  } finally {
    d.sqlite.close();
  }
});
it("Giao DH phải đủ món, đúng khách và còn hạn; HD không được thiếu consume", async () => {
  const d = fixture();
  try {
    await send(d.db, "create", hold());
    const event = release();
    Object.assign(event.row, { kind: "consume", related_document_id: "hd" });
    const hd: SyncRecord = {
      table: "documents",
      row: {
        id: "hd",
        type: "HD",
        kind: "sale",
        issued_at: now,
        customer_id: "c1",
        metadata_json: JSON.stringify({ reservation_id: "dh" }),
      },
    };
    const line = {
      ...hold()[1],
      row: { ...hold()[1].row, document_id: "hd", quantity: 6 },
    };
    await expect(
      validateReservations(d.db, actor, [hd, line, event]),
    ).rejects.toThrow("giao đủ");
    line.row.quantity = 7;
    await expect(
      validateReservations(d.db, actor, [hd, line, event]),
    ).resolves.toEqual(new Set());
    await expect(validateReservations(d.db, actor, [hd, line])).rejects.toThrow(
      "thiếu sự kiện",
    );
    event.row.created_at = expiry;
    hd.row.issued_at = expiry;
    await expect(
      validateReservations(d.db, actor, [hd, line, event]),
    ).rejects.toThrow();
  } finally {
    d.sqlite.close();
  }
});
