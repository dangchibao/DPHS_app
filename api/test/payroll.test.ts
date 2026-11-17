import { it, expect } from "vitest";
import { testDatabase } from "./database";
import {
  payrollPreview,
  payrollPush,
  payrollPull,
  syncCheckpoint,
} from "../src/payroll";
import { push, pull } from "../src/sync";
import type { Actor } from "../src/auth";
const id = (n: number) =>
  `019c4b00-0000-7000-8000-${String(n).padStart(12, "0")}`;
const actor: Actor = {
  user_id: "u1",
  store_id: "s1",
  device_id: "d1",
  role: "owner",
  issued_role: "owner",
  name: "Chủ",
  session_id: "session",
  session_kind: "interactive",
};
const rule = {
  base_salary: 5200000,
  standard_days: 26,
  commission_bps: 100,
  bonus_tiers: [{ threshold: 1000000, amount: 10000 }],
};
const now = () => new Date().toISOString();
function fixture() {
  const d = testDatabase();
  d.sqlite
    .exec(`INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'2019-01-01');
  INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','2019-01-01');
  INSERT INTO users VALUES('u1','owner','Chủ','hash','salt',1,0,'2019-01-01'),('u2','staff','Nhân viên','hash','salt',1,0,'2019-01-01');
  INSERT INTO employee_store_assignments VALUES('a1','s1','u1','owner',1,'2019-01-01'),('a2','s1','u2','cashier',1,'2019-01-01');
  INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES('p1','Áo','Áo sơ mi','Unisex','Tiểu học','2020','2019-01-01');
  INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES('v1','p1','SKU','M','Trắng','cái',50000,100000,'2019-01-01');
  INSERT INTO documents VALUES('hd','s1','d1','HD','sale','HD-test','2020-01-10T00:00:00.000Z','u1',NULL,NULL,1000000,100000,900000,'2020','{}');
  INSERT INTO invoice_lines VALUES('line','s1','hd','v1','Áo','M','Trắng','cái',10,100000,50000,100000,'v1');
  INSERT INTO documents VALUES('mr','s1','d1','MR','tailoring','MR-test','2020-01-10T00:00:00.000Z','u1',NULL,NULL,200000,0,200000,'2020','{}');
  INSERT INTO documents VALUES('dt','s1','d1','DT','exchange','DT-test','2020-01-11T00:00:00.000Z','u2',NULL,'hd',60000,0,60000,'2020','{}');
  INSERT INTO invoice_lines VALUES('new','s1','dt','v1','Áo','M','Trắng','cái',1,30000,10000,0,'v1');
  INSERT INTO return_lines VALUES('ret','s1','dt','line',1,90000,0);
  INSERT INTO documents VALUES('dh','s1','d1','DH','reservation','DH-test','2020-01-10T00:00:00.000Z','u1',NULL,NULL,999999,0,999999,'2020','{}');
  INSERT INTO documents VALUES('ck','s1','d1','CK','transfer_out','CK-test','2020-01-10T00:00:00.000Z','u1',NULL,NULL,0,0,0,'2020','{}');
  INSERT INTO attendance_entries VALUES('a','s1','d1','u1','u1','2020-01-10',1,'Nửa ngày','2020-01-10T00:00:00.000Z','1'),('b','s1','d1','u1','u1','2020-01-10',2,'Đủ ngày','2020-01-10T01:00:00.000Z','2'),('c','s1','d1','u1','u1','2020-01-11',1,'Nửa ngày','2020-01-11T00:00:00.000Z','1');`);
  return d;
}
function command(n: number, kind: string, payload: unknown, extra = {}) {
  return {
    mutations: [
      {
        id: id(n + 1000),
        records: [
          {
            table: "payroll_commands",
            row: {
              id: id(n),
              store_id: "s1",
              device_id: "d1",
              user_id: "u1",
              kind,
              payload_json: JSON.stringify(payload),
              created_at: now(),
              ...extra,
            },
          },
        ],
      },
    ],
  };
}
async function send(
  d: ReturnType<typeof fixture>,
  n: number,
  kind: string,
  payload: unknown,
) {
  return (await (
    await payrollPush(d.db, actor, command(n, kind, payload))
  ).json()) as {
    acknowledged: string[];
    outcomes: { status: string; message: string }[];
  };
}
async function setup(d: ReturnType<typeof fixture>) {
  expect(
    (
      await send(d, 1, "rule", {
        employee_id: "u1",
        effective_month: "2020-01",
        previous_id: null,
        config: rule,
      })
    ).outcomes[0].status,
  ).toBe("accepted");
  const cursor = Number(
    d.sqlite
      .prepare(
        "SELECT MAX(server_seq) AS n FROM change_feed WHERE store_id='s1'",
      )
      .get()?.n ?? 0,
  );
  await syncCheckpoint(d.db, actor, { drained: true, cursor });
}
it("Lương CAS/idempotent, không đưa số lương vào feed/audit công khai hoặc ACK nền", async () => {
  const d = fixture();
  try {
    const request = command(1, "rule", {
      employee_id: "u1",
      effective_month: "2020-01",
      previous_id: null,
      config: rule,
    });
    const result = await (await payrollPush(d.db, actor, request)).json();
    expect(JSON.stringify(result)).not.toContain("5200000");
    await payrollPush(d.db, actor, request);
    const retryWithNewEnvelope = {
      ...request,
      mutations: [{ ...request.mutations[0], id: id(9000) }],
    };
    expect(
      (
        (await (
          await payrollPush(d.db, actor, retryWithNewEnvelope)
        ).json()) as { acknowledged: string[] }
      ).acknowledged,
    ).toEqual([id(9000)]);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM compensation_versions").get()
        ?.n,
    ).toBe(1);
    expect(
      (
        await send(d, 2, "rule", {
          employee_id: "u1",
          effective_month: "2020-01",
          previous_id: null,
          config: rule,
        })
      ).outcomes[0].status,
    ).toBe("rejected");
    expect(
      (
        await send(d, 3, "rule", {
          employee_id: "u1",
          effective_month: "2020-01",
          previous_id: id(1),
          config: { ...rule, base_salary: 6000000 },
        })
      ).outcomes[0].status,
    ).toBe("accepted");
    await expect(
      payrollPush(d.db, actor, {
        ...request,
        mutations: [
          {
            ...request.mutations[0],
            records: [
              {
                ...request.mutations[0].records[0],
                row: {
                  ...request.mutations[0].records[0].row,
                  payload_json: "{}",
                },
              },
            ],
          },
        ],
      }),
    ).rejects.toThrow("nội dung khác");
    const publicFeed = await (
      await pull(d.db, actor, new URL("https://test/sync/pull?scope=store"))
    ).text();
    expect(publicFeed).not.toContain("base_salary");
    expect(publicFeed).not.toContain("5200000");
    expect(
      JSON.stringify(d.sqlite.prepare("SELECT * FROM audit_logs").all()),
    ).not.toContain("5200000");
    const privateFeed = await (
      await payrollPull(d.db, actor, new URL("https://test/payroll/pull"))
    ).text();
    expect(privateFeed).toContain("5200000");
    for (const role of ["manager", "cashier", "warehouse"] as const)
      await expect(
        payrollPull(
          d.db,
          { ...actor, role },
          new URL("https://test/payroll/pull"),
        ),
      ).rejects.toThrow();
    await expect(
      payrollPull(
        d.db,
        { ...actor, session_kind: "sync" },
        new URL("https://test/payroll/pull"),
      ),
    ).rejects.toThrow();
    await expect(
      payrollPush(d.db, { ...actor, issued_role: "cashier" }, request),
    ).rejects.toThrow();
    await expect(
      push(d.db, actor, {
        mutations: [
          {
            id: id(9),
            records: [
              {
                table: "compensation_versions",
                row: { id: id(99), store_id: "s1" },
              },
            ],
          },
        ],
      }),
    ).rejects.toThrow();
  } finally {
    d.sqlite.close();
  }
});
it("Nguồn doanh số đúng HD/MR + món thay DT − credit gốc; chốt/khóa/hủy/phát hành lại bất biến", async () => {
  const d = fixture();
  try {
    await setup(d);
    const quote = await payrollPreview(d.db, actor, "u1", "2020-01");
    expect(quote.sources).toMatchObject({
      net_sales: 1010000,
      attendance_units: 3,
    });
    expect(quote.totals).toMatchObject({
      base_pay: 300000,
      commission_pay: 10100,
      bonus_pay: 10000,
      total_pay: 320100,
    });
    const issued = await send(d, 2, "issue", {
      employee_id: "u1",
      month: "2020-01",
      quote_hash: quote.quote_hash,
      confirm_reconciled: true,
    });
    expect(issued.outcomes[0].status).toBe("accepted");
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM payroll_locks").get()?.n,
    ).toBe(1);
    expect(() =>
      d.sqlite.exec(
        "UPDATE payroll_runs SET employee_name='Giả' WHERE id='" + id(2) + "'",
      ),
    ).toThrow("append-only");
    expect(() =>
      d.sqlite.exec(
        "INSERT INTO attendance_entries VALUES('late','s1','d1','u1','u1','2020-01-12',2,'Muộn','2020-01-12T00:00:00.000Z','4')",
      ),
    ).toThrow("LOCKED");
    const again = await payrollPreview(d.db, actor, "u1", "2020-01");
    expect(
      (
        await send(d, 3, "issue", {
          employee_id: "u1",
          month: "2020-01",
          quote_hash: again.quote_hash,
          confirm_reconciled: true,
        })
      ).outcomes[0].status,
    ).toBe("rejected");
    expect(
      (await send(d, 4, "void", { run_id: id(2), reason: "Đối soát lại kỳ" }))
        .outcomes[0].status,
    ).toBe("accepted");
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM payroll_lock_releases").get()
        ?.n,
    ).toBe(1);
    const next = await payrollPreview(d.db, actor, "u1", "2020-01");
    expect(
      (
        await send(d, 5, "issue", {
          employee_id: "u1",
          month: "2020-01",
          quote_hash: next.quote_hash,
          confirm_reconciled: true,
        })
      ).outcomes[0].status,
    ).toBe("accepted");
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM payroll_runs").get()?.n,
    ).toBe(2);
  } finally {
    d.sqlite.close();
  }
});
it("Máy chưa đối soát chặn chốt; snapshot cũ hoặc race giữa preview/commit không phát hành nhầm", async () => {
  const d = fixture();
  try {
    await setup(d);
    d.sqlite.exec(
      "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d2','s1','B3','Máy chưa gửi','approved','2019-01-01')",
    );
    let quote = await payrollPreview(d.db, actor, "u1", "2020-01");
    expect(
      (
        await send(d, 2, "issue", {
          employee_id: "u1",
          month: "2020-01",
          quote_hash: quote.quote_hash,
          confirm_reconciled: true,
        })
      ).outcomes[0].message,
    ).toContain("Còn máy");
    const cursor = Number(
      d.sqlite
        .prepare(
          "SELECT MAX(server_seq) AS n FROM change_feed WHERE store_id='s1'",
        )
        .get()?.n ?? 0,
    );
    await expect(
      syncCheckpoint(
        d.db,
        { ...actor, device_id: "d2" },
        { drained: false, cursor },
      ),
    ).rejects.toThrow();
    await syncCheckpoint(
      d.db,
      { ...actor, device_id: "d2" },
      { drained: true, cursor },
    );
    quote = await payrollPreview(d.db, actor, "u1", "2020-01");
    await send(d, 3, "rule", {
      employee_id: "u1",
      effective_month: "2020-01",
      previous_id: id(1),
      config: { ...rule, base_salary: 6000000 },
    });
    expect(
      (
        await send(d, 4, "issue", {
          employee_id: "u1",
          month: "2020-01",
          quote_hash: quote.quote_hash,
          confirm_reconciled: true,
        })
      ).outcomes[0].status,
    ).toBe("rejected");
    quote = await payrollPreview(d.db, actor, "u1", "2020-01");
    const original = d.db.batch.bind(d.db);
    let injected = false;
    d.db.batch = (async (statements: D1PreparedStatement[]) => {
      if (statements.length >= 9 && !injected) {
        injected = true;
        d.sqlite
          .prepare(
            "INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) VALUES('s1','race','documents','race','{}',?)",
          )
          .run(now());
      }
      return original(statements);
    }) as D1Database["batch"];
    expect(
      (
        await send(d, 5, "issue", {
          employee_id: "u1",
          month: "2020-01",
          quote_hash: quote.quote_hash,
          confirm_reconciled: true,
        })
      ).outcomes[0].status,
    ).toBe("rejected");
    expect(injected).toBe(true);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM payroll_runs").get()?.n,
    ).toBe(0);
  } finally {
    d.sqlite.close();
  }
});
it("Giao dịch tới muộn đánh dấu đối soát, không sửa snapshot phiếu; không rò flag sang cửa hàng khác", async () => {
  const d = fixture();
  try {
    await setup(d);
    const quote = await payrollPreview(d.db, actor, "u1", "2020-01");
    await send(d, 2, "issue", {
      employee_id: "u1",
      month: "2020-01",
      quote_hash: quote.quote_hash,
      confirm_reconciled: true,
    });
    const before = d.sqlite
      .prepare("SELECT totals_json FROM payroll_runs")
      .get()?.totals_json;
    d.sqlite.exec(
      "INSERT INTO documents VALUES('late','s1','d1','HD','sale','HD-late','2020-01-13T00:00:00.000Z','u1',NULL,NULL,10000,0,10000,'2020','{}')",
    );
    expect(
      d.sqlite
        .prepare("SELECT COUNT(*) AS n FROM payroll_reconciliations")
        .get()?.n,
    ).toBe(1);
    expect(
      d.sqlite.prepare("SELECT totals_json FROM payroll_runs").get()
        ?.totals_json,
    ).toBe(before);
    await send(d, 3, "rule", {
      employee_id: "u2",
      effective_month: "2020-01",
      previous_id: null,
      config: rule,
    });
    const secondQuote = await payrollPreview(d.db, actor, "u2", "2020-01");
    await send(d, 4, "issue", {
      employee_id: "u2",
      month: "2020-01",
      quote_hash: secondQuote.quote_hash,
      confirm_reconciled: true,
    });
    d.sqlite.exec(
      "INSERT INTO documents VALUES('late-dt','s1','d1','DT','exchange','DT-late','2020-01-14T00:00:00.000Z','u2',NULL,'hd',89000,0,89000,'2020','{}'); INSERT INTO invoice_lines VALUES('late-new','s1','late-dt','v1','Áo','M','Trắng','cái',1,1000,10000,0,'v1'); INSERT INTO return_lines VALUES('late-ret','s1','late-dt','line',1,90000,1);",
    );
    expect(
      d.sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM payroll_reconciliations WHERE document_id='late-dt'",
        )
        .get()?.n,
    ).toBe(2);
    expect(
      (
        (await (
          await payrollPull(
            d.db,
            { ...actor, store_id: "other" },
            new URL("https://test/payroll/pull"),
          )
        ).json()) as { events: unknown[] }
      ).events,
    ).toEqual([]);
  } finally {
    d.sqlite.close();
  }
});
