import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { testDatabase } from "./database";
import { push } from "../src/sync";
import type { Actor } from "../src/auth";
import type { SyncRecord } from "../src/sync";

describe("Hóa đơn tại API", () => {
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
  beforeEach(() => {
    database = testDatabase();
    database.sqlite
      .exec(`INSERT INTO stores VALUES ('s1','NT-CN01','CN01',1,'${now}');
   INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d1','s1','A2','Máy 1','approved','${now}');
   INSERT INTO users VALUES ('u1','admin','Chủ','hash','salt',1,0,'${now}');
   INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES ('p1','Áo','Áo sơ mi','Unisex','Tiểu học','2026–2027','${now}');
   INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at,lww_key) VALUES ('v1','p1','SKU1','M','Trắng','cái',50000,100000,'${now}','version1');
   INSERT INTO stock_movements VALUES ('initial','s1','d1','v1',10,'receipt',NULL,'Nhập','u1','${now}');`);
  });
  afterEach(() => database.sqlite.close());
  const config = {
    school_id: null,
    customer_kind: null,
    starts_at: null,
    ends_at: null,
    min_total: 0,
    min_quantity: 1,
    allow_combo: false,
    allow_price_list: false,
    prices: {},
    discount_type: "fixed",
    value: 1000,
    voucher: "",
  };
  async function commercial(
    id: string,
    kind: string,
    overrides: Record<string, unknown> = {},
    active = 1,
    revision = "v1",
  ) {
    const row = {
      id,
      store_id: "s1",
      name: id,
      kind,
      config_json: JSON.stringify({ ...config, ...overrides }),
      active,
      updated_at: now,
      lww_key: `${now}|d1|${revision}`,
    };
    await push(database.db, actor, {
      mutations: [
        {
          id: `rule-${id}-${revision}`,
          records: [{ table: "commercial_rules", row }],
        },
      ],
    });
    return { id, version: row.lww_key };
  }
  function discounted(
    price: number,
    discount: number,
    metadata: Record<string, unknown>,
  ) {
    const data = records();
    Object.assign(data.find((r) => r.table === "documents")!.row, {
      subtotal: price,
      discount,
      total: price - discount,
      metadata_json: JSON.stringify(metadata),
    });
    Object.assign(data.find((r) => r.table === "invoice_lines")!.row, {
      unit_price: price,
      discount,
    });
    Object.assign(data.find((r) => r.table === "payments")!.row, {
      amount: price - discount,
    });
    return data;
  }
  it("API tính lại bảng giá và khuyến mãi theo revision, không tin số giảm client", async () => {
    const list = await commercial("price-list", "price_list", {
      discount_type: "none",
      value: 0,
      prices: { v1: 80000 },
    });
    const promotion = await commercial("promo", "promotion", {
      discount_type: "percent",
      value: 1000,
      allow_price_list: true,
    });
    const metadata = {
      price_list: list,
      promotion,
      promotion_discount: 8000,
      manual_discount: 0,
      regular_subtotal: 80000,
    };
    await expect(
      push(database.db, actor, {
        mutations: [
          {
            id: "forged-discount",
            records: discounted(80000, 9000, {
              ...metadata,
              promotion_discount: 9000,
            }),
          },
        ],
      }),
    ).rejects.toThrow("không khớp");
    await push(
      database.db,
      { ...actor, role: "cashier", issued_role: "cashier" },
      {
        mutations: [
          { id: "approved-sale", records: discounted(80000, 8000, metadata) },
        ],
      },
    );
    expect(
      database.sqlite.prepare("SELECT total FROM documents").get()?.total,
    ).toBe(72000);
    expect(
      database.sqlite.prepare("SELECT quantity FROM stock_balances").get()
        ?.quantity,
    ).toBe(9);
  });
  it("Không chấp nhận cộng giảm thủ công trá hình, vẫn nhận revision offline đã duyệt", async () => {
    const promotion = await commercial("promo", "promotion", { value: 50000 });
    await commercial("promo", "promotion", { value: 1000 }, 0, "v2");
    await expect(
      push(database.db, actor, {
        mutations: [
          {
            id: "hidden-manual",
            records: discounted(100000, 50001, {
              promotion,
              promotion_discount: 50000,
            }),
          },
        ],
      }),
    ).rejects.toThrow("thủ công");
    const data = discounted(100000, 50000, {
      promotion,
      promotion_discount: 50000,
      manual_discount: 0,
    });
    await push(
      database.db,
      { ...actor, role: "cashier" },
      { mutations: [{ id: "offline-version", records: data }] },
    );
    await push(
      database.db,
      { ...actor, role: "cashier" },
      { mutations: [{ id: "offline-version", records: data }] },
    );
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM documents").get()?.n,
    ).toBe(1);
    expect(
      database.sqlite.prepare("SELECT total FROM documents").get()?.total,
    ).toBe(50000);
  });
  it("Thu ngân không tự tạo giá hoặc nâng khách thành đại lý để dùng bảng giá", async () => {
    await expect(
      push(
        database.db,
        { ...actor, role: "cashier" },
        {
          mutations: [
            {
              id: "rule-hack",
              records: [
                {
                  table: "commercial_rules",
                  row: {
                    id: "x",
                    store_id: "s1",
                    name: "x",
                    kind: "promotion",
                    config_json: JSON.stringify(config),
                    active: 1,
                    updated_at: now,
                    lww_key: `${now}|d1|x`,
                  },
                },
              ],
            },
          ],
        },
      ),
    ).rejects.toThrow("quyền");
    await expect(
      push(
        database.db,
        { ...actor, role: "cashier" },
        {
          mutations: [
            {
              id: "dealer-hack",
              records: [
                {
                  table: "customers",
                  row: {
                    id: "fake-dealer",
                    store_id: "s1",
                    name: "Sai",
                    phone: "",
                    kind: "dealer",
                    updated_at: now,
                    lww_key: `${now}|d1|x`,
                  },
                },
              ],
            },
          ],
        },
      ),
    ).rejects.toThrow("quyền");
  });
  it("MR xác minh phụ thu, không xuất hàng sẵn, đặt cọc/thu nợ và trạng thái có thứ tự", async () => {
    const rule = {
      id: "tailor-rule",
      store_id: "s1",
      name: "Phụ thu may",
      config_json: JSON.stringify({
        base_fee: 20000,
        rates: {},
        options: { rush: { label: "May gấp", amount: 5000 } },
      }),
      active: 1,
      updated_at: now,
      lww_key: `${now}|d1|v1`,
    };
    await push(database.db, actor, {
      mutations: [
        {
          id: "tailor-rule",
          records: [{ table: "tailoring_rules", row: rule }],
        },
      ],
    });
    await push(database.db, actor, {
      mutations: [
        {
          id: "tailor-rule-new",
          records: [
            {
              table: "tailoring_rules",
              row: { ...rule, active: 0, lww_key: `${now}|d1|v2` },
            },
          ],
        },
      ],
    });
    const data = records().filter((r) => r.table !== "stock_movements");
    const measurements = {
      chest: 1000,
      waist: 1000,
      hips: 1000,
      shirt_length: 1000,
      trousers_length: 1000,
      shoulder: 1000,
      height: 1000,
      weight: 70000,
    };
    const due = new Date(Date.now() + 7 * 86400000 + 7 * 3600000)
      .toISOString()
      .slice(0, 10);
    const tailoring = {
      rule_name: rule.name,
      option_labels: ["May gấp"],
      rule: { id: rule.id, version: rule.lww_key },
      measurements,
      options: ["rush"],
      due_date: due,
      notes: "Thêm túi",
      per_unit_fee: 25000,
    };
    Object.assign(data.find((r) => r.table === "documents")!.row, {
      type: "MR",
      kind: "tailoring",
      code: `MR-CN01-A2-${day}-001`,
      customer_id: "custom-parent",
      subtotal: 125000,
      total: 125000,
      metadata_json: JSON.stringify({ tailoring }),
    });
    Object.assign(data.find((r) => r.table === "invoice_lines")!.row, {
      unit_price: 125000,
      size: "May riêng",
    });
    Object.assign(data.find((r) => r.table === "payments")!.row, {
      amount: 25000,
    });
    data.unshift({
      table: "customers",
      row: {
        id: "custom-parent",
        store_id: "s1",
        name: "Phụ huynh may",
        phone: "",
        kind: "parent",
        updated_at: now,
        lww_key: `${now}|d1|customer`,
      },
    });
    data.push({
      table: "receivable_entries",
      row: {
        id: "custom-debt",
        store_id: "s1",
        customer_id: "custom-parent",
        document_id: "inv1",
        payment_id: null,
        amount: 100000,
        due_date: due,
        created_at: now,
      },
    });
    const malformed = structuredClone(data);
    malformed.find((r) => r.table === "documents")!.row.metadata_json =
      JSON.stringify({ tailoring: { ...tailoring, per_unit_fee: 20000 } });
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "wrong-fee", records: malformed }],
      }),
    ).rejects.toThrow("không khớp");
    await push(database.db, actor, {
      mutations: [{ id: "custom-sale", records: data }],
    });
    expect(
      database.sqlite.prepare("SELECT quantity FROM stock_balances").get()
        ?.quantity,
    ).toBe(10);
    const event = (type: string, id: string): SyncRecord => ({
      table: "document_events",
      row: {
        id,
        store_id: "s1",
        document_id: "inv1",
        type,
        related_id: null,
        reason: "Chuyển bước",
        user_id: "u1",
        created_at: now,
      },
    });
    await expect(
      push(database.db, actor, {
        mutations: [
          { id: "skip-step", records: [event("TAILOR_READY", "skip")] },
        ],
      }),
    ).rejects.toThrow("TAILOR_STEP_ORDER");
    const sewing = event("TAILOR_SEWING", "sewing");
    await push(
      database.db,
      { ...actor, role: "warehouse" },
      { mutations: [{ id: "sewing", records: [sewing] }] },
    );
    await push(
      database.db,
      { ...actor, role: "warehouse" },
      { mutations: [{ id: "sewing-again", records: [sewing] }] },
    );
    await push(database.db, actor, {
      mutations: [{ id: "ready", records: [event("TAILOR_READY", "ready")] }],
    });
    await push(
      database.db,
      { ...actor, role: "accountant" },
      {
        mutations: [
          {
            id: "tailor-collection",
            records: [
              {
                table: "payments",
                row: {
                  id: "tailor-payment",
                  store_id: "s1",
                  device_id: "d1",
                  document_id: "inv1",
                  user_id: "u1",
                  amount: 100000,
                  method: "bank",
                  direction: "receive",
                  created_at: now,
                  note: "Tất toán may",
                },
              },
              {
                table: "receivable_entries",
                row: {
                  id: "tailor-collection-debt",
                  store_id: "s1",
                  customer_id: "custom-parent",
                  document_id: "inv1",
                  payment_id: "tailor-payment",
                  amount: -100000,
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
      database.sqlite
        .prepare("SELECT SUM(amount) AS balance FROM receivable_entries")
        .get()?.balance,
    ).toBe(0);
    await push(database.db, actor, {
      mutations: [
        { id: "delivered", records: [event("TAILOR_DELIVERED", "delivered")] },
      ],
    });
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM document_events").get()
        ?.n,
    ).toBe(3);
    await expect(
      push(
        database.db,
        { ...actor, device_id: "different-device" },
        {
          mutations: [
            {
              id: "wrong-device",
              records: [event("TAILOR_SEWING", "different")],
            },
          ],
        },
      ),
    ).rejects.toThrow("máy lập phiếu");
  });
  function records(): SyncRecord[] {
    return [
      {
        table: "documents",
        row: {
          id: "inv1",
          store_id: "s1",
          device_id: "d1",
          type: "HD",
          kind: "sale",
          code: `HD-CN01-A2-${day}-001`,
          issued_at: now,
          user_id: "u1",
          customer_id: null,
          original_id: null,
          subtotal: 100000,
          discount: 0,
          total: 100000,
          school_year: "2026–2027",
          metadata_json: "{}",
        },
      },
      {
        table: "invoice_lines",
        row: {
          id: "line1",
          store_id: "s1",
          document_id: "inv1",
          variant_id: "v1",
          name: "Áo",
          size: "M",
          color: "Trắng",
          unit: "cái",
          quantity: 1,
          unit_price: 100000,
          unit_cost: 50000,
          discount: 0,
          price_version: "version1",
        },
      },
      {
        table: "payments",
        row: {
          id: "pay1",
          store_id: "s1",
          device_id: "d1",
          document_id: "inv1",
          user_id: "u1",
          amount: 100000,
          method: "cash",
          direction: "receive",
          created_at: now,
          note: "",
        },
      },
      {
        table: "stock_movements",
        row: {
          id: "move1",
          store_id: "s1",
          device_id: "d1",
          variant_id: "v1",
          quantity: -1,
          kind: "sale",
          document_id: "inv1",
          reason: "Bán hàng",
          user_id: "u1",
          created_at: now,
        },
      },
    ];
  }
  it("Ghi hóa đơn/kho/thanh toán nguyên tử và retry idempotent", async () => {
    const body = { mutations: [{ id: "sale1", records: records() }] };
    await push(database.db, actor, body);
    await push(database.db, actor, body);
    expect(
      database.sqlite.prepare("SELECT quantity FROM stock_balances").get()
        ?.quantity,
    ).toBe(9);
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM payments").get()?.n,
    ).toBe(1);
    expect(() => database.sqlite.exec("DELETE FROM documents")).toThrow();
  });
  it("Gắn học sinh đúng phụ huynh và giữ nguyên snapshot trường sau khi đổi tên", async () => {
    database.sqlite
      .exec(`INSERT INTO customers VALUES('school-customer','s1','Trường','','school','${now}','school-customer-v1'),('parent','s1','Phụ huynh','','parent','${now}','parent-v1');
      INSERT INTO schools VALUES('school','s1','Trường gốc','Tiểu học','school-customer',1,'${now}','school-v1');
      INSERT INTO school_classes VALUES('class','s1','school','2A','2026–2027',1,'${now}','class-v1');
      INSERT INTO students VALUES('student','s1','class','HS001','Nguyễn An','parent',1,'${now}','student-v1');`);
    const sale = records();
    sale[0].row.customer_id = "parent";
    sale[0].row.metadata_json = JSON.stringify({
      school_id: "school",
      student_id: "student",
      school_name: "Trường gốc",
      student_name: "Nguyễn An",
    });
    await push(database.db, actor, {
      mutations: [{ id: "student-sale", records: sale }],
    });
    database.sqlite.exec(
      "UPDATE schools SET name='Tên trường mới' WHERE id='school'",
    );
    expect(
      JSON.parse(
        String(
          database.sqlite.prepare("SELECT metadata_json FROM documents").get()
            ?.metadata_json,
        ),
      ).school_name,
    ).toBe("Trường gốc");
    const foreign = records();
    foreign[0].row.metadata_json = JSON.stringify({ school_id: "missing" });
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "bad-school", records: foreign }],
      }),
    ).rejects.toThrow("cửa hàng");
  });
  it("Giữ giá của revision offline thua LWW để nhận hóa đơn đã phát hành", async () => {
    database.sqlite.exec(
      "UPDATE product_variants SET lww_key='2020-01-01T00:00:00.000Z|d1|seed' WHERE id='v1'",
    );
    const base = database.sqlite
      .prepare("SELECT * FROM product_variants WHERE id='v1'")
      .get()!;
    const newer = {
      ...base,
      price: 120000,
      updated_at: now,
      lww_key: `${now}|d1|new`,
    };
    const olderTime = new Date(Date.now() - 60000).toISOString();
    const older = {
      ...base,
      price: 100000,
      updated_at: olderTime,
      lww_key: `${olderTime}|d1|old`,
    };
    for (const [id, row] of [
      ["new", newer],
      ["old", older],
    ] as const) {
      await push(database.db, actor, {
        mutations: [{ id, records: [{ table: "product_variants", row }] }],
      });
    }
    expect(
      database.sqlite
        .prepare("SELECT price FROM product_variants WHERE id='v1'")
        .get()?.price,
    ).toBe(120000);
    const sale = records();
    sale[1].row.price_version = older.lww_key;
    await push(database.db, actor, {
      mutations: [{ id: "sale-old-price", records: sale }],
    });
    expect(
      database.sqlite
        .prepare("SELECT total FROM documents WHERE id='inv1'")
        .get()?.total,
    ).toBe(100000);
    await expect(
      push(database.db, actor, {
        mutations: [
          {
            id: "forged-version",
            records: [
              { table: "product_variants", row: { ...older, price: 1 } },
            ],
          },
        ],
      }),
    ).rejects.toThrow("PRICE_VERSION_CONFLICT");
    expect(
      database.sqlite
        .prepare("SELECT price FROM variant_price_history WHERE version=?")
        .get(older.lww_key)?.price,
    ).toBe(100000);
  });
  it("Không chấp nhận giá giả hoặc số tiền không khớp", async () => {
    const forged = records();
    forged[1].row.unit_cost = 1;
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "sale1", records: forged }],
      }),
    ).rejects.toThrow("phiên bản giá");
    const total = records();
    total[0].row.total = 1;
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "sale2", records: total }],
      }),
    ).rejects.toThrow("Tổng hóa đơn");
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM documents").get()?.n,
    ).toBe(0);
  });
  it("Không cho bỏ xuất kho hoặc thu vượt giá trị hóa đơn", async () => {
    await expect(
      push(database.db, actor, {
        mutations: [
          {
            id: "sale1",
            records: records().filter((r) => r.table !== "stock_movements"),
          },
        ],
      }),
    ).rejects.toThrow("Xuất kho");
    const overpaid = records();
    overpaid[2].row.amount = 200000;
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "sale2", records: overpaid }],
      }),
    ).rejects.toThrow("lớn hơn");
  });
  it("Thu nhiều lần không đổi hóa đơn, retry không nhân đôi và rollback khi vượt nợ", async () => {
    const sale = records();
    sale[0].row.customer_id = "c1";
    sale[2].row.amount = 30000;
    sale.unshift({
      table: "customers",
      row: {
        id: "c1",
        store_id: "s1",
        name: "Phụ huynh",
        phone: "0900000000",
        kind: "parent",
        updated_at: now,
        lww_key: `${now}|d1|customer`,
      },
    });
    sale.push({
      table: "receivable_entries",
      row: {
        id: "debt1",
        store_id: "s1",
        customer_id: "c1",
        document_id: "inv1",
        payment_id: null,
        amount: 70000,
        due_date: "2026-12-15",
        created_at: now,
      },
    });
    await push(database.db, actor, {
      mutations: [{ id: "sale-deposit", records: sale }],
    });
    const collection = (id: string, amount: number): SyncRecord[] => [
      {
        table: "payments",
        row: {
          id,
          store_id: "s1",
          device_id: "d1",
          document_id: "inv1",
          user_id: "u1",
          amount,
          method: "bank",
          direction: "receive",
          created_at: now,
          note: "Thu công nợ",
        },
      },
      {
        table: "receivable_entries",
        row: {
          id: `debt-${id}`,
          store_id: "s1",
          customer_id: "c1",
          document_id: "inv1",
          payment_id: id,
          amount: -amount,
          due_date: "",
          created_at: now,
        },
      },
    ];
    const body = {
      mutations: [{ id: "collection1", records: collection("pay2", 40000) }],
    };
    await push(database.db, actor, body);
    await push(database.db, actor, body);
    await expect(
      push(database.db, actor, {
        mutations: [{ id: "overpay", records: collection("pay3", 30001) }],
      }),
    ).rejects.toThrow("RECEIVABLE_OVERPAYMENT");
    expect(
      database.sqlite
        .prepare("SELECT COUNT(*) AS n FROM payments WHERE id='pay3'")
        .get()?.n,
    ).toBe(0);
    expect(
      database.sqlite
        .prepare("SELECT SUM(amount) AS balance FROM receivable_entries")
        .get()?.balance,
    ).toBe(30000);
    await expect(
      push(
        database.db,
        { ...actor, device_id: "other-device" },
        {
          mutations: [
            { id: "foreign-device", records: collection("pay4", 10000) },
          ],
        },
      ),
    ).rejects.toThrow("thiết bị");
    await push(database.db, actor, {
      mutations: [{ id: "collection2", records: collection("pay5", 30000) }],
    });
    expect(
      database.sqlite
        .prepare("SELECT SUM(amount) AS balance FROM receivable_entries")
        .get()?.balance,
    ).toBe(0);
    expect(
      database.sqlite.prepare("SELECT total FROM documents").get()?.total,
    ).toBe(100000);
  });
});
