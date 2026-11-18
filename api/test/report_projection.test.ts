import { it, expect } from "vitest";
import { dailyUpsert } from "../src/report_projection";
import type { SyncRecord } from "../src/sync";
import { actor, fixture, sale, apply, metrics } from "./report_fixtures";
it("Cache atomic chống replay khác envelope, thu tiền nhiều lần không cộng lại doanh thu", async () => {
  const d = fixture();
  try {
    const records = sale();
    await apply(d, records);
    expect(metrics(d)).toMatchObject({
      revenue: "200000",
      cost: "100000",
      quantity: "2",
      payment_in: "100000",
      invoices: "1",
      "p|p1|revenue": "200000",
    });
    await apply(d, records);
    expect(metrics(d).revenue).toBe("200000");
    expect(metrics(d).payment_in).toBe("100000");
    const extra: SyncRecord = {
      table: "payments",
      row: { ...records[2].row, id: "pay2", amount: 100000 },
    };
    await apply(d, [extra]);
    await apply(d, [extra]);
    expect(metrics(d).revenue).toBe("200000");
    expect(metrics(d).payment_in).toBe("200000");
    expect(
      JSON.parse(
        d.sqlite.prepare("SELECT payment_ids_json FROM report_receipts").get()
          ?.payment_ids_json as string,
      ),
    ).toEqual(["hd-pay", "pay2"]);
  } finally {
    d.sqlite.close();
  }
});
it("DT cộng món thay, trừ credit/giá vốn đúng người bán gốc, không lấy chênh lệch", async () => {
  const d = fixture();
  try {
    await apply(d, sale());
    const dt: SyncRecord[] = [
      {
        table: "documents",
        row: {
          ...sale()[0].row,
          id: "dt",
          type: "DT",
          kind: "exchange",
          code: "DT-test",
          user_id: "u2",
          original_id: "hd",
          subtotal: 20000,
          total: 20000,
        },
      },
      {
        table: "invoice_lines",
        row: {
          ...sale()[1].row,
          id: "dt-line",
          document_id: "dt",
          quantity: 1,
          unit_price: 120000,
        },
      },
      {
        table: "return_lines",
        row: {
          id: "ret",
          store_id: "s1",
          document_id: "dt",
          original_line_id: "hd-line",
          quantity: 1,
          credit: 100000,
          base_returned: 0,
        },
      },
      {
        table: "payments",
        row: {
          ...sale()[2].row,
          id: "dt-pay",
          document_id: "dt",
          user_id: "u2",
          amount: 20000,
        },
      },
    ];
    await apply(d, dt, { ...actor, user_id: "u2", name: "Thu ngân" });
    await apply(d, dt, { ...actor, user_id: "u2", name: "Thu ngân" });
    expect(metrics(d)).toMatchObject({
      revenue: "220000",
      cost: "100000",
      quantity: "2",
      payment_in: "120000",
      returns: "1",
      "e|u1|revenue": "100000",
      "e|u2|revenue": "120000",
    });
  } finally {
    d.sqlite.close();
  }
});
it("Rollback cache lỗi không để ledger/receipt nửa chừng; overflow không chặn ghi sổ", async () => {
  const d = fixture();
  try {
    d.sqlite.exec(
      "CREATE TRIGGER fail_report BEFORE INSERT ON daily_reports BEGIN SELECT RAISE(ABORT,'injected_failure'); END;",
    );
    await expect(apply(d, sale())).rejects.toThrow("injected_failure");
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM documents").get()?.n,
    ).toBe(0);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM report_receipts").get()?.n,
    ).toBe(0);
    d.sqlite.exec("DROP TRIGGER fail_report");
    await apply(d, sale("big", 100000, 9007199254740991));
    expect(
      d.sqlite.prepare("SELECT overflow FROM daily_reports").get()?.overflow,
    ).toBe(1);
    expect(
      d.sqlite.prepare("SELECT COUNT(*) AS n FROM documents").get()?.n,
    ).toBe(1);
  } finally {
    d.sqlite.close();
  }
});
it("SQL cộng int64 có kiểm overflow, nhãn/cap blob không làm phát sinh float hoặc chặn ledger", async () => {
  const d = fixture();
  try {
    d.sqlite
      .prepare("INSERT INTO report_receipts VALUES(?,?,?,?)")
      .run("s1", "doc", "[]", "token");
    const delta = {
      store: "s1",
      day: "2026-11-15",
      year: "2026–2027",
      school: "",
      metrics: { revenue: "9223372036854775807", "label|p|p1": "Áo" },
      overflow: 0,
    };
    await d.db.batch([dailyUpsert(d.db, delta, "doc", "token")]);
    await d.db.batch([
      dailyUpsert(
        d.db,
        { ...delta, metrics: { revenue: "1", "label|p|p1": "Áo sơ mi" } },
        "doc",
        "token",
      ),
    ]);
    expect(
      d.sqlite.prepare("SELECT overflow FROM daily_reports").get()?.overflow,
    ).toBe(1);
    expect(metrics(d).revenue).toBe("0");
    expect(metrics(d)["label|p|p1"]).toBe("Áo sơ mi");
    await d.db.batch([
      dailyUpsert(
        d.db,
        {
          ...delta,
          day: "2026-11-16",
          metrics: { "label|p|p1": "x".repeat(300000) },
        },
        "doc",
        "token",
      ),
    ]);
    const capped = d.sqlite
      .prepare("SELECT * FROM daily_reports WHERE day='2026-11-16'")
      .get();
    expect(capped?.overflow).toBe(1);
    expect(capped?.metrics_json).toBe("{}");
  } finally {
    d.sqlite.close();
  }
});
