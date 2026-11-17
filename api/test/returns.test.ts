import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { push, type SyncRecord } from "../src/sync";
import type { Actor } from "../src/auth";

const now = new Date().toISOString(),
  day = new Date(Date.now() + 7 * 3600000)
    .toISOString()
    .slice(0, 10)
    .replaceAll("-", "");
const actor: Actor = {
  user_id: "u1",
  store_id: "s1",
  device_id: "d1",
  role: "owner",
  name: "Chủ",
  session_id: "session",
};
function fixture(balance = 0) {
  const database = testDatabase(),
    s = database.sqlite;
  s.exec(`INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'${now}');
    INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','${now}');
    INSERT INTO users VALUES('u1','admin','Chủ','hash','salt',1,0,'${now}');
    INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES('p1','Áo','Áo sơ mi','Unisex','Tiểu học','2026–2027','${now}');
    INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at,lww_key) VALUES('v1','p1','SKU-M','M','Trắng','cái',50000,100000,'${now}','price1'),('v2','p1','SKU-L','L','Trắng','cái',50000,150000,'${now}','price2');
    INSERT INTO customers VALUES('c1','s1','Phụ huynh','','parent','${now}','customer-version');
    INSERT INTO documents VALUES('original','s1','d1','HD','sale','HD-CN01-A2-${day}-001','${now}','u1','c1',NULL,300000,199999,100001,'2026–2027','{}');
    INSERT INTO invoice_lines VALUES('original-line','s1','original','v1','Áo','M','Trắng','cái',3,100000,50000,199999,'price1');
    INSERT INTO payments VALUES('original-pay','s1','d1','original','u1',${100001 - balance},'cash','receive','${now}','Bán');
    INSERT INTO stock_movements VALUES('initial1','s1','d1','v1',10,'receipt',NULL,'Nhập','u1','${now}'),('sold','s1','d1','v1',-3,'sale','original','Bán','u1','${now}'),('initial2','s1','d1','v2',10,'receipt',NULL,'Nhập','u1','${now}');`);
  if (balance)
    s.prepare(
      "INSERT INTO receivable_entries VALUES('original-debt','s1','c1','original',NULL,?,'2099-01-01',?)",
    ).run(balance, now);
  return database;
}
type Choice = {
  id: string;
  quantity: number;
  credit: number;
  before: number;
  balance?: number;
  original?: string;
  line?: string;
  variant?: string;
  sizeExchange?: boolean;
  void?: boolean;
};
function bundle(c: Choice): SyncRecord[] {
  const original = c.original ?? "original",
    line = c.line ?? "original-line",
    variant = c.variant ?? "v1",
    offset = Math.min(c.balance ?? 0, c.credit),
    replacement = c.sizeExchange ? c.credit : 0,
    due = replacement - c.credit + offset,
    refund = Math.max(0, -due);
  const metadata = {
    original_code:
      original === "original"
        ? `HD-CN01-A2-${day}-001`
        : `DT-CN01-A2-${day}-${original.replaceAll(/\D/g, "").padStart(3, "0")}`,
    reason: "Đổi/trả",
    void_original: c.void === true,
    replacements: c.sizeExchange
      ? [{ variant_id: "v2", quantity: c.quantity, source_line_id: line }]
      : [],
    returned_value: c.credit,
    replacement_value: replacement,
    debt_offset: offset,
    cash_due: due,
    refund,
    received: 0,
    new_debt: Math.max(0, due),
    total: Math.abs(due),
  };
  const data: SyncRecord[] = [
    {
      table: "documents",
      row: {
        id: c.id,
        store_id: "s1",
        device_id: "d1",
        type: "DT",
        kind: c.sizeExchange ? "exchange" : "return",
        code: `DT-CN01-A2-${day}-${c.id.replaceAll(/\D/g, "").padStart(3, "0")}`,
        issued_at: now,
        user_id: "u1",
        customer_id: "c1",
        original_id: original,
        subtotal: Math.abs(due),
        discount: 0,
        total: Math.abs(due),
        school_year: "2026–2027",
        metadata_json: JSON.stringify(metadata),
      },
    },
    {
      table: "return_lines",
      row: {
        id: `${c.id}-return`,
        store_id: "s1",
        document_id: c.id,
        original_line_id: line,
        quantity: c.quantity,
        credit: c.credit,
        base_returned: c.before,
      },
    },
    {
      table: "stock_movements",
      row: {
        id: `${c.id}-in`,
        store_id: "s1",
        device_id: "d1",
        variant_id: variant,
        quantity: c.quantity,
        kind: "return",
        document_id: c.id,
        reason: "Nhận lại",
        user_id: "u1",
        created_at: now,
      },
    },
  ];
  if (c.sizeExchange) {
    const unit = Math.ceil(c.credit / c.quantity);
    data.splice(2, 0, {
      table: "invoice_lines",
      row: {
        id: `${c.id}-new-line`,
        store_id: "s1",
        document_id: c.id,
        variant_id: "v2",
        name: "Áo",
        size: "L",
        color: "Trắng",
        unit: "cái",
        quantity: c.quantity,
        unit_price: unit,
        unit_cost: 50000,
        discount: unit * c.quantity - c.credit,
        price_version: "price2",
      },
    });
    data.push({
      table: "stock_movements",
      row: {
        id: `${c.id}-out`,
        store_id: "s1",
        device_id: "d1",
        variant_id: "v2",
        quantity: -c.quantity,
        kind: "sale",
        document_id: c.id,
        reason: "Thay thế",
        user_id: "u1",
        created_at: now,
      },
    });
  }
  if (refund)
    data.push({
      table: "payments",
      row: {
        id: `${c.id}-refund`,
        store_id: "s1",
        device_id: "d1",
        document_id: c.id,
        user_id: "u1",
        amount: refund,
        method: "cash",
        direction: "refund",
        created_at: now,
        note: "Hoàn tiền",
      },
    });
  if (offset)
    data.push({
      table: "receivable_adjustments",
      row: {
        id: `${c.id}-credit`,
        store_id: "s1",
        customer_id: "c1",
        document_id: original,
        credit_document_id: c.id,
        amount: -offset,
        created_at: now,
      },
    });
  if (due > 0)
    data.push({
      table: "receivable_entries",
      row: {
        id: `${c.id}-debt`,
        store_id: "s1",
        customer_id: "c1",
        document_id: c.id,
        payment_id: null,
        amount: due,
        due_date: "2099-01-01",
        created_at: now,
      },
    });
  if (c.void)
    data.push({
      table: "document_events",
      row: {
        id: `${c.id}-void`,
        store_id: "s1",
        document_id: original,
        type: "CANCELLED",
        related_id: c.id,
        reason: "Đổi/trả",
        user_id: "u1",
        created_at: now,
      },
    });
  return data;
}
it("Lô client cũ 5 mutation được ack 3+2, nằm trong 50 D1 calls và 32 đối số JSON", async () => {
  const { db, sqlite } = fixture();
  let calls = 0;
  function count() {
    calls++;
    if (calls > 50) throw new Error("D1 invocation query budget exceeded");
  }
  function statement(value: D1PreparedStatement): D1PreparedStatement {
    return new Proxy(value, {
      get(target, key) {
        if (key === "bind")
          return (...args: unknown[]) => statement(target.bind(...args));
        if (["first", "all", "run", "raw"].includes(String(key)))
          return (...args: unknown[]) => {
            count();
            return (
              Reflect.get(target, key) as (...args: unknown[]) => unknown
            )(...args);
          };
        return Reflect.get(target, key);
      },
    });
  }
  const counted = new Proxy(db, {
    get(target, key) {
      if (key === "prepare")
        return (sql: string) => statement(target.prepare(sql));
      if (key === "batch")
        return (rows: D1PreparedStatement[]) => {
          count();
          return target.batch(rows);
        };
      return Reflect.get(target, key);
    },
  });
  sqlite.function("json_object", { varargs: true }, (...args) => {
    if (args.length > 32)
      throw new Error("D1 SQL function argument limit exceeded");
    const value: Record<string, unknown> = {};
    for (let i = 0; i < args.length; i += 2)
      value[String(args[i])] = args[i + 1];
    return JSON.stringify(value);
  });
  try {
    const first = [0, 1, 2].map((i) => ({
      id: `budget${i}`,
      records: bundle({
        id: `dt${i + 1}`,
        quantity: 1,
        credit: [33333, 33334, 33334][i],
        before: i,
      }),
    }));
    const mutations = [
      ...first,
      { id: "budget3", records: first[0].records },
      { id: "budget4", records: first[1].records },
    ];
    const result = (await (
      await push(counted, actor, { mutations })
    ).json()) as { acknowledged: string[] };
    expect(result.acknowledged).toEqual(["budget0", "budget1", "budget2"]);
    expect(calls).toBeLessThanOrEqual(50);
    const payload = JSON.parse(
      String(
        sqlite
          .prepare(
            "SELECT payload FROM change_feed WHERE entity_type='audit_logs' LIMIT 1",
          )
          .get()?.payload,
      ),
    );
    expect(Object.keys(payload)).toHaveLength(18);
    expect(payload.document_code).toBeDefined();
    expect(payload.hash).toBeTruthy();
    calls = 0;
    expect(
      (
        (await (
          await push(counted, actor, { mutations: mutations.slice(3) })
        ).json()) as { acknowledged: string[] }
      ).acknowledged,
    ).toEqual(["budget3", "budget4"]);
    expect(
      sqlite
        .prepare("SELECT COUNT(*) AS n FROM documents WHERE type='DT'")
        .get()?.n,
    ).toBe(3);
  } finally {
    sqlite.close();
  }
});
it("Hoàn từng phần đúng tổng; retry không nhân đôi; chặn thêm dòng vào DT đã phát hành", async () => {
  const { db, sqlite } = fixture();
  try {
    let first: SyncRecord[] = [];
    for (let i = 0; i < 3; i++) {
      const data = bundle({
        id: `dt${i + 1}`,
        quantity: 1,
        credit: [33333, 33334, 33334][i],
        before: i,
      });
      if (i === 0) first = data;
      await push(db, actor, { mutations: [{ id: `job${i}`, records: data }] });
      await push(db, actor, { mutations: [{ id: `job${i}`, records: data }] });
    }
    expect(
      sqlite.prepare("SELECT SUM(credit) AS credit FROM return_lines").get()
        ?.credit,
    ).toBe(100001);
    expect(
      sqlite
        .prepare(
          "SELECT SUM(amount) AS refund FROM payments WHERE direction='refund'",
        )
        .get()?.refund,
    ).toBe(100001);
    expect(
      sqlite
        .prepare("SELECT quantity FROM stock_balances WHERE variant_id='v1'")
        .get()?.quantity,
    ).toBe(10);
    const extra = {
      ...first.find((r) => r.table === "stock_movements")!,
      row: {
        ...first.find((r) => r.table === "stock_movements")!.row,
        id: "extra-in",
      },
    };
    await expect(
      push(db, actor, {
        mutations: [{ id: "append-hack", records: [...first, extra] }],
      }),
    ).rejects.toMatchObject({ code: "IMMUTABLE_DOCUMENT" });
  } finally {
    sqlite.close();
  }
});
it("Cấn hết nợ, hoàn đúng phần đã nhận và chặn thu lại sau cấn", async () => {
  const { db, sqlite } = fixture(60000);
  try {
    await push(db, actor, {
      mutations: [
        {
          id: "return-debt",
          records: bundle({
            id: "dt1",
            quantity: 3,
            credit: 100001,
            before: 0,
            balance: 60000,
          }),
        },
      ],
    });
    expect(
      sqlite
        .prepare(
          "SELECT SUM(amount) AS balance FROM receivable_ledger WHERE document_id='original'",
        )
        .get()?.balance,
    ).toBe(0);
    expect(
      sqlite
        .prepare("SELECT amount FROM payments WHERE direction='refund'")
        .get()?.amount,
    ).toBe(40001);
    const payment = {
      id: "overpay",
      store_id: "s1",
      device_id: "d1",
      document_id: "original",
      user_id: "u1",
      amount: 1,
      method: "cash",
      direction: "receive",
      created_at: now,
      note: "Sai",
    };
    await expect(
      push(db, actor, {
        mutations: [
          {
            id: "overpay",
            records: [
              { table: "payments", row: payment },
              {
                table: "receivable_entries",
                row: {
                  id: "overpay-debt",
                  store_id: "s1",
                  customer_id: "c1",
                  document_id: "original",
                  payment_id: "overpay",
                  amount: -1,
                  due_date: "",
                  created_at: now,
                },
              },
            ],
          },
        ],
      }),
    ).rejects.toThrow("RECEIVABLE_OVERPAYMENT");
  } finally {
    sqlite.close();
  }
});
it("Đổi size giữ giá sau giảm và có thể hoàn tiếp món thay thế", async () => {
  const { db, sqlite } = fixture();
  try {
    await push(db, actor, {
      mutations: [
        {
          id: "size",
          records: bundle({
            id: "dt1",
            quantity: 3,
            credit: 100001,
            before: 0,
            sizeExchange: true,
          }),
        },
      ],
    });
    expect(
      sqlite
        .prepare(
          "SELECT unit_price,discount FROM invoice_lines WHERE id='dt1-new-line'",
        )
        .get(),
    ).toMatchObject({ unit_price: 33334, discount: 1 });
    await push(db, actor, {
      mutations: [
        {
          id: "return-size",
          records: bundle({
            id: "dt2",
            original: "dt1",
            line: "dt1-new-line",
            variant: "v2",
            quantity: 3,
            credit: 100001,
            before: 0,
          }),
        },
      ],
    });
    expect(
      sqlite
        .prepare("SELECT quantity FROM stock_balances WHERE variant_id='v2'")
        .get()?.quantity,
    ).toBe(10);
    expect(
      sqlite
        .prepare(
          "SELECT SUM(amount) AS refund FROM payments WHERE direction='refund'",
        )
        .get()?.refund,
    ).toBe(100001);
  } finally {
    sqlite.close();
  }
});
it("Đổi theo giá hiện tại tạo nợ đúng chênh lệch và thu được trên DT", async () => {
  const { db, sqlite } = fixture();
  try {
    const data = bundle({
      id: "dt1",
      quantity: 1,
      credit: 33333,
      before: 0,
      sizeExchange: true,
    });
    const doc = data.find((r) => r.table === "documents")!.row,
      m = JSON.parse(String(doc.metadata_json));
    m.replacements[0].source_line_id = null;
    Object.assign(m, {
      replacement_value: 150000,
      cash_due: 116667,
      new_debt: 116667,
      total: 116667,
    });
    Object.assign(doc, {
      subtotal: 116667,
      total: 116667,
      metadata_json: JSON.stringify(m),
    });
    Object.assign(data.find((r) => r.table === "invoice_lines")!.row, {
      unit_price: 150000,
      discount: 0,
    });
    data.push({
      table: "receivable_entries",
      row: {
        id: "new-debt",
        store_id: "s1",
        customer_id: "c1",
        document_id: "dt1",
        payment_id: null,
        amount: 116667,
        due_date: "2099-01-01",
        created_at: now,
      },
    });
    await push(db, actor, {
      mutations: [{ id: "retail-exchange", records: data }],
    });
    expect(
      sqlite
        .prepare(
          "SELECT SUM(amount) AS balance FROM receivable_ledger WHERE document_id='dt1'",
        )
        .get()?.balance,
    ).toBe(116667);
    await push(
      db,
      { ...actor, role: "accountant" },
      {
        mutations: [
          {
            id: "collect-dt",
            records: [
              {
                table: "payments",
                row: {
                  id: "dt-pay",
                  store_id: "s1",
                  device_id: "d1",
                  document_id: "dt1",
                  user_id: "u1",
                  amount: 116667,
                  method: "bank",
                  direction: "receive",
                  created_at: now,
                  note: "Thu chênh lệch",
                },
              },
              {
                table: "receivable_entries",
                row: {
                  id: "dt-debt-paid",
                  store_id: "s1",
                  customer_id: "c1",
                  document_id: "dt1",
                  payment_id: "dt-pay",
                  amount: -116667,
                  due_date: "",
                  created_at: now,
                },
              },
            ],
          },
        ],
      },
    );
    expect(
      sqlite
        .prepare(
          "SELECT SUM(amount) AS balance FROM receivable_ledger WHERE document_id='dt1'",
        )
        .get()?.balance,
    ).toBe(0);
  } finally {
    sqlite.close();
  }
});
it("Hủy đúng quyền, không sửa gốc; từ chối trả vượt hoặc thiếu máy gốc", async () => {
  const { db, sqlite } = fixture();
  try {
    const data = bundle({
      id: "dt1",
      quantity: 3,
      credit: 100001,
      before: 0,
      void: true,
    });
    await expect(
      push(
        db,
        { ...actor, role: "cashier" },
        { mutations: [{ id: "void-denied", records: data }] },
      ),
    ).rejects.toThrow("quyền");
    await expect(
      push(
        db,
        { ...actor, device_id: "other" },
        { mutations: [{ id: "device-denied", records: data }] },
      ),
    ).rejects.toThrow("máy đã lập");
    await expect(
      push(db, actor, {
        mutations: [
          {
            id: "too-many",
            records: bundle({
              id: "dt2",
              quantity: 4,
              credit: 100001,
              before: 0,
            }),
          },
        ],
      }),
    ).rejects.toThrow("vượt");
    await push(db, actor, { mutations: [{ id: "void", records: data }] });
    expect(
      sqlite.prepare("SELECT total FROM documents WHERE id='original'").get()
        ?.total,
    ).toBe(100001);
    expect(
      sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM document_events WHERE type='CANCELLED'",
        )
        .get()?.n,
    ).toBe(1);
  } finally {
    sqlite.close();
  }
});
