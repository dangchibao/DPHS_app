import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { push, type SyncRecord } from "../src/sync";
import type { Actor } from "../src/auth";
const now = new Date().toISOString(),
  day = new Date(Date.parse(now) + 7 * 3600000)
    .toISOString()
    .slice(0, 10)
    .replaceAll("-", "");
const source: Actor = {
    user_id: "u1",
    store_id: "s1",
    device_id: "d1",
    role: "warehouse",
    name: "Kho CN01",
    session_id: "a",
  },
  target: Actor = {
    user_id: "u2",
    store_id: "s2",
    device_id: "d2",
    role: "warehouse",
    name: "Kho CN02",
    session_id: "b",
  };
function fixture() {
  const d = testDatabase();
  d.sqlite
    .exec(`INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'${now}'),('s2','NT-CN02','CN02',1,'${now}');
  INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Nguồn','approved','${now}'),('d2','s2','B3','Nhận','approved','${now}'),('d3','s2','B4','Máy khác','approved','${now}');
  INSERT INTO users VALUES('u1','kho1','Kho CN01','hash','salt',1,0,'${now}'),('u2','kho2','Kho CN02','hash','salt',1,0,'${now}');
  INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES('p1','Áo','Áo','Unisex','Tiểu học','2026','${now}');
  INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at,lww_key) VALUES('v1','p1','SKU1','M','Trắng','cái',50000,100000,'${now}','version1');
  INSERT INTO stock_movements VALUES('initial','s1','d1','v1',10,'receipt',NULL,'Nhập','u1','${now}');`);
  return d;
}
function out(): SyncRecord[] {
  return [
    {
      table: "documents",
      row: {
        id: "out",
        store_id: "s1",
        device_id: "d1",
        type: "CK",
        kind: "transfer_out",
        code: `CK-CN01-A2-${day}-001`,
        issued_at: now,
        user_id: "u1",
        customer_id: null,
        original_id: null,
        subtotal: 0,
        discount: 0,
        total: 0,
        school_year: "2026",
        metadata_json: JSON.stringify({
          target_store_id: "s2",
          target_device_id: "d2",
          target_store_code: "NT-CN02",
          target_device_code: "B3",
          notes: "Điều hàng CN02",
        }),
      },
    },
    {
      table: "invoice_lines",
      row: {
        id: "out-line",
        store_id: "s1",
        document_id: "out",
        variant_id: "v1",
        name: "Áo",
        size: "M",
        color: "Trắng",
        unit: "cái",
        quantity: 5,
        unit_price: 0,
        unit_cost: 50000,
        discount: 0,
        price_version: "version1",
      },
    },
    {
      table: "stock_movements",
      row: {
        id: "out-stock",
        store_id: "s1",
        device_id: "d1",
        variant_id: "v1",
        quantity: -5,
        kind: "transfer_out",
        document_id: "out",
        reason: "Chuyển CN02",
        user_id: "u1",
        created_at: now,
      },
    },
  ];
}
const dispatch = (): SyncRecord[] => [
  {
    table: "transfer_events",
    row: {
      id: "dispatch",
      store_id: "s1",
      device_id: "d1",
      document_id: "out",
      user_id: "u1",
      reason: "Giao vận chuyển",
      created_at: now,
    },
  },
];
function receive(quantity = 4): SyncRecord[] {
  return [
    {
      table: "documents",
      row: {
        id: "in",
        store_id: "s2",
        device_id: "d2",
        type: "CK",
        kind: "transfer_in",
        code: `CK-CN02-B3-${day}-001`,
        issued_at: now,
        user_id: "u2",
        customer_id: null,
        original_id: null,
        subtotal: 0,
        discount: 0,
        total: 0,
        school_year: "2026",
        metadata_json: JSON.stringify({ offer_id: "out" }),
      },
    },
    ...(quantity > 0
      ? [
          {
            table: "invoice_lines",
            row: {
              id: "in-line",
              store_id: "s2",
              document_id: "in",
              variant_id: "v1",
              name: "Áo",
              size: "M",
              color: "Trắng",
              unit: "cái",
              quantity,
              unit_price: 0,
              unit_cost: 50000,
              discount: 0,
              price_version: "version1",
            },
          },
        ]
      : []),
    {
      table: "transfer_receipts",
      row: {
        id: "in",
        store_id: "s2",
        device_id: "d2",
        offer_id: "out",
        user_id: "u2",
        counts_json: JSON.stringify([{ variant_id: "v1", quantity }]),
        reason: "Đã kiểm đếm số thực nhận",
        created_at: now,
      },
    },
    ...(quantity > 0
      ? [
          {
            table: "stock_movements",
            row: {
              id: "in-stock",
              store_id: "s2",
              device_id: "d2",
              variant_id: "v1",
              quantity,
              kind: "transfer_in",
              document_id: "in",
              reason: "Nhận CK",
              user_id: "u2",
              created_at: now,
            },
          },
        ]
      : []),
  ];
}
const send = (
  d: D1Database,
  id: string,
  records: SyncRecord[],
  actor = source,
) => push(d, actor, { mutations: [{ id, records }] });
it("Xuất → đang chuyển → nhận thiếu, projection đúng store và replay không nhân đôi", async () => {
  const d = fixture();
  try {
    await send(d.db, "out", out());
    expect(
      d.sqlite
        .prepare("SELECT quantity FROM stock_balances WHERE store_id='s1'")
        .get()?.quantity,
    ).toBe(5);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM transfer_offers").get()?.n,
    ).toBe(0);
    await send(d.db, "dispatch", dispatch());
    const offer = d.sqlite.prepare("SELECT * FROM transfer_offers").get();
    expect(offer?.store_id).toBe("s2");
    expect(offer?.device_id).toBe("d2");
    d.sqlite.exec(
      "UPDATE product_variants SET cost=80000,lww_key='version2' WHERE id='v1'",
    );
    await send(d.db, "receive", receive(), target);
    for (const [id, records, actor] of [
      ["out-repeat", out(), source],
      ["dispatch-repeat", dispatch(), source],
      ["receive-repeat", receive(), target],
    ] as const)
      await send(d.db, id, records, actor);
    expect(
      d.sqlite
        .prepare("SELECT quantity FROM stock_balances WHERE store_id='s1'")
        .get()?.quantity,
    ).toBe(5);
    expect(
      d.sqlite
        .prepare("SELECT quantity FROM stock_balances WHERE store_id='s2'")
        .get()?.quantity,
    ).toBe(4);
    expect(
      d.sqlite
        .prepare("SELECT store_id,document_id FROM transfer_deliveries")
        .get(),
    ).toMatchObject({ store_id: "s1", document_id: "out" });
    expect(
      d.sqlite
        .prepare("SELECT unit_cost FROM invoice_lines WHERE document_id='in'")
        .get()?.unit_cost,
    ).toBe(50000);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM transfer_receipts").get()?.n,
    ).toBe(1);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM payments").get()?.n,
    ).toBe(0);
    expect(
      d.sqlite
        .prepare(
          "SELECT store_id FROM change_feed WHERE entity_type='transfer_offers'",
        )
        .get()?.store_id,
    ).toBe("s2");
  } finally {
    d.sqlite.close();
  }
});
it("Chặn máy nhận khác, vai trò sai, snapshot giả và nhận lần hai", async () => {
  const d = fixture();
  try {
    await expect(
      send(d.db, "deny", out(), { ...source, role: "cashier" }),
    ).rejects.toThrow();
    await send(d.db, "out", out());
    await send(d.db, "dispatch", dispatch());
    await expect(
      send(d.db, "wrong", receive(), { ...target, device_id: "d3" }),
    ).rejects.toThrow();
    const forged = receive();
    forged.find((r) => r.table === "invoice_lines")!.row.unit_cost = 80000;
    await expect(send(d.db, "forged", forged, target)).rejects.toThrow(
      "Snapshot",
    );
    await send(d.db, "receive", receive(), target);
    const again = receive();
    for (const r of again) {
      if (r.table === "documents" || r.table === "transfer_receipts")
        r.row.id = "in2";
      if ("document_id" in r.row) r.row.document_id = "in2";
    }
    await expect(send(d.db, "again", again, target)).rejects.toThrow("đã nhận");
  } finally {
    d.sqlite.close();
  }
});
it("Nhận 0 hoặc nhận dư phải có lý do, không điều chỉnh tự động nguồn", async () => {
  for (const n of [0, 7]) {
    const d = fixture();
    try {
      await send(d.db, "out", out());
      await send(d.db, "dispatch", dispatch());
      const invalid = receive(n);
      invalid.find((r) => r.table === "transfer_receipts")!.row.reason = "";
      await expect(send(d.db, "no-reason", invalid, target)).rejects.toThrow(
        "Lý do",
      );
      await send(d.db, "receive", receive(n), target);
      expect(
        d.sqlite
          .prepare(
            "SELECT COALESCE(SUM(quantity),0) AS n FROM stock_movements WHERE store_id='s2'",
          )
          .get()?.n,
      ).toBe(n);
      expect(
        d.sqlite
          .prepare("SELECT quantity FROM stock_balances WHERE store_id='s1'")
          .get()?.quantity,
      ).toBe(5);
    } finally {
      d.sqlite.close();
    }
  }
});
it("Lỗi ghi projection rollback dispatch và processed mutation", async () => {
  const d = fixture();
  try {
    await send(d.db, "out", out());
    d.sqlite.exec(
      "CREATE TRIGGER fail_offer BEFORE INSERT ON change_feed WHEN NEW.entity_type='transfer_offers' BEGIN SELECT RAISE(ABORT,'INJECTED'); END;",
    );
    await expect(send(d.db, "dispatch", dispatch())).rejects.toThrow(
      "INJECTED",
    );
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM transfer_events").get()?.n,
    ).toBe(0);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM transfer_offers").get()?.n,
    ).toBe(0);
    expect(
      d.sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM processed_mutations WHERE id='dispatch'",
        )
        .get()?.n,
    ).toBe(0);
    d.sqlite.exec("DROP TRIGGER fail_offer");
    await send(d.db, "dispatch", dispatch());
  } finally {
    d.sqlite.close();
  }
});

it("Client không được ghi projection và batch 3 CK nằm trong 50 D1 calls", async () => {
  const d = fixture();
  try {
    let calls = 0;
    const wrap = (s: D1PreparedStatement): D1PreparedStatement =>
      ({
        ...s,
        bind: (...values: unknown[]) => wrap(s.bind(...values)),
        first: (...args: []) => {
          calls++;
          return s.first(...args);
        },
        all: () => {
          calls++;
          return s.all();
        },
        run: () => {
          calls++;
          return s.run();
        },
      }) as D1PreparedStatement;
    const counted = {
      prepare: (sql: string) => wrap(d.db.prepare(sql)),
      batch: (statements: D1PreparedStatement[]) => {
        calls++;
        return d.db.batch(statements);
      },
    } as D1Database;
    const mutations = [1, 2, 3].map((n) => {
      const records = out();
      for (const r of records) {
        r.row.id = `${r.table}-${n}`;
        if (r.table === "documents") {
          r.row.id = `out-${n}`;
          r.row.code = `CK-CN01-A2-${day}-${String(n).padStart(3, "0")}`;
        }
        if ("document_id" in r.row) r.row.document_id = `out-${n}`;
        if (r.table === "invoice_lines") r.row.quantity = 1;
        if (r.table === "stock_movements") r.row.quantity = -1;
      }
      return { id: `mutation-${n}`, records };
    });
    await push(counted, source, { mutations });
    expect(calls).toBeLessThanOrEqual(50);
    await expect(
      send(
        d.db,
        "forged-projection",
        [{ table: "transfer_offers", row: { id: "fake", store_id: "s2" } }],
        target,
      ),
    ).rejects.toThrow("Loại dữ liệu");
  } finally {
    d.sqlite.close();
  }
});
