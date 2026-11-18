import type { Actor } from "./auth";
import type { SyncRecord } from "./sync";
import { reportLimits } from "./config";

type Row = Record<string, unknown>;
type Delta = {
  store: string;
  day: string;
  year: string;
  school: string;
  metrics: Record<string, string>;
  overflow: number;
};
const max = 9223372036854775807n,
  min = -9223372036854775808n;
const overflowSql =
  "CASE WHEN b>0 THEN a>9223372036854775807-b WHEN b<0 THEN a<(-9223372036854775807-1)-b ELSE 0 END";
export function dailyUpsert(
  db: D1Database,
  delta: Delta,
  document: string,
  token: string,
): D1PreparedStatement {
  let encoded = JSON.stringify(delta.metrics),
    overflow = delta.overflow;
  if (new TextEncoder().encode(encoded).byteLength > reportLimits.cacheBytes) {
    encoded = "{}";
    overflow = 1;
  }
  const within = `length(CAST(daily_reports.metrics_json AS BLOB))+length(CAST(excluded.metrics_json AS BLOB))<=${reportLimits.cacheBytes}`;
  return db
    .prepare(
      `INSERT INTO daily_reports(store_id,day,school_year,school_id,metrics_json,overflow)
    SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM report_receipts WHERE store_id=? AND document_id=? AND last_token=?)
    ON CONFLICT(store_id,day,school_year,school_id) DO UPDATE SET (metrics_json,overflow)=(
      WITH entries AS (SELECT key,value,0 AS src FROM json_each(daily_reports.metrics_json) WHERE ${within} UNION ALL SELECT key,value,1 FROM json_each(excluded.metrics_json) WHERE ${within}),
      folded AS (SELECT key,MAX(CASE WHEN src=0 THEN value END) AS old_text,MAX(CASE WHEN src=1 THEN value END) AS new_text,
        COALESCE(MAX(CASE WHEN src=0 AND key NOT LIKE 'label|%' THEN CAST(value AS INTEGER) END),0) AS a,
        COALESCE(MAX(CASE WHEN src=1 AND key NOT LIKE 'label|%' THEN CAST(value AS INTEGER) END),0) AS b FROM entries GROUP BY key),
      merged AS (SELECT key,CASE WHEN key LIKE 'label|%' THEN COALESCE(new_text,old_text) WHEN ${overflowSql} THEN '0' ELSE CAST(a+b AS TEXT) END AS value,
        CASE WHEN key NOT LIKE 'label|%' THEN ${overflowSql} ELSE 0 END AS bad FROM folded)
      SELECT CASE WHEN ${within} THEN json_group_object(key,value) ELSE daily_reports.metrics_json END,MAX(COALESCE(MAX(bad),0),daily_reports.overflow,excluded.overflow,CASE WHEN ${within} THEN 0 ELSE 1 END) FROM merged)
  `,
    )
    .bind(
      delta.store,
      delta.day,
      delta.year,
      delta.school,
      encoded,
      overflow,
      delta.store,
      document,
      token,
    );
}
function numeric(delta: Delta, key: string, value: bigint) {
  const amount = BigInt(delta.metrics[key] ?? "0") + value;
  if (amount > max || amount < min) {
    delta.overflow = 1;
    delta.metrics[key] = "0";
  } else {
    delta.metrics[key] = amount.toString();
  }
}
const quantity = (row: Row) => BigInt(row.quantity as number),
  money = (v: unknown) => BigInt(v as number);
const sizeKey = (size: string) =>
  Array.from(new TextEncoder().encode(size), (b) =>
    b.toString(16).padStart(2, "0"),
  )
    .join("")
    .toUpperCase();

/** Derived cache only. Receipt tokens gate every UPSERT inside the ledger transaction,
 * including retries with a different outbox envelope ID. No per-line markers. */
export async function reportProjection(
  db: D1Database,
  actor: Actor,
  records: SyncRecord[],
): Promise<D1PreparedStatement[]> {
  const incomingDocuments = records
    .filter(
      (r) =>
        r.table === "documents" &&
        ["HD", "MR", "DT"].includes(String(r.row.type)),
    )
    .map((r) => r.row);
  const incomingPayments = records
    .filter((r) => r.table === "payments")
    .map((r) => r.row);
  if (!incomingDocuments.length && !incomingPayments.length) return [];
  const ids = Array.from(
      new Set([
        ...incomingDocuments.map((d) => d.id),
        ...incomingPayments.map((p) => p.document_id),
      ]),
    ),
    encoded = JSON.stringify(ids);
  const inputLines = records
      .filter((r) => r.table === "invoice_lines")
      .map((r) => r.row),
    inputReturns = records
      .filter((r) => r.table === "return_lines")
      .map((r) => r.row);
  const results = await db.batch<Row>([
    db
      .prepare(
        "SELECT d.*,u.display_name AS employee_name FROM documents d JOIN users u ON u.id=d.user_id WHERE d.store_id=? AND d.id IN (SELECT value FROM json_each(?))",
      )
      .bind(actor.store_id, encoded),
    db
      .prepare(
        "SELECT * FROM invoice_lines WHERE store_id=? AND document_id IN (SELECT value FROM json_each(?))",
      )
      .bind(actor.store_id, encoded),
    db
      .prepare(
        "SELECT * FROM return_lines WHERE store_id=? AND document_id IN (SELECT value FROM json_each(?))",
      )
      .bind(actor.store_id, encoded),
    db
      .prepare(
        "SELECT * FROM payments WHERE store_id=? AND document_id IN (SELECT value FROM json_each(?))",
      )
      .bind(actor.store_id, encoded),
    db
      .prepare(
        "SELECT v.id,v.product_id FROM product_variants v WHERE v.id IN (SELECT value FROM json_each(?) UNION SELECT variant_id FROM invoice_lines WHERE store_id=? AND document_id IN (SELECT value FROM json_each(?)))",
      )
      .bind(
        JSON.stringify(inputLines.map((l) => l.variant_id)),
        actor.store_id,
        encoded,
      ),
    db
      .prepare(
        "SELECT l.*,o.user_id AS employee_id,u.display_name AS employee_name,v.product_id FROM invoice_lines l JOIN documents o ON o.store_id=l.store_id AND o.id=l.document_id JOIN product_variants v ON v.id=l.variant_id JOIN users u ON u.id=o.user_id WHERE l.store_id=? AND l.id IN (SELECT value FROM json_each(?) UNION SELECT original_line_id FROM return_lines WHERE store_id=? AND document_id IN (SELECT value FROM json_each(?)))",
      )
      .bind(
        actor.store_id,
        JSON.stringify(inputReturns.map((r) => r.original_line_id)),
        actor.store_id,
        encoded,
      ),
  ]);
  const documents = new Map(results[0].results.map((r) => [r.id, r]));
  for (const row of incomingDocuments) {
    documents.set(row.id, {
      ...documents.get(row.id),
      ...row,
      employee_name: documents.get(row.id)?.employee_name ?? actor.name,
    });
  }
  const merge = (old: Row[], next: Row[]) =>
    Array.from(new Map([...old, ...next].map((r) => [r.id, r])).values());
  const lines = merge(results[1].results, inputLines),
    returns = merge(results[2].results, inputReturns),
    payments = merge(results[3].results, incomingPayments);
  const variants = new Map(results[4].results.map((r) => [r.id, r.product_id]));
  for (const r of records.filter((r) => r.table === "product_variants"))
    variants.set(r.row.id, r.row.product_id);
  const originals = new Map(results[5].results.map((r) => [r.id, r]));
  const statements: D1PreparedStatement[] = [];
  for (const document of documents.values()) {
    if (!["HD", "MR", "DT"].includes(String(document.type))) continue;
    const metadata = JSON.parse(String(document.metadata_json)) as Row;
    const groups = new Map<string, Delta>();
    const group = (stamp: string) => {
      const day = new Date(Date.parse(stamp) + 7 * 3600000)
        .toISOString()
        .slice(0, 10);
      const key = JSON.stringify([
        day,
        document.school_year,
        metadata.school_id ?? "",
      ]);
      let delta = groups.get(key);
      if (!delta) {
        delta = {
          store: actor.store_id,
          day,
          year: String(document.school_year),
          school: String(metadata.school_id ?? ""),
          metrics: Object.create(null) as Record<string, string>,
          overflow: 0,
        };
        groups.set(key, delta);
      }
      return delta;
    };
    const base = group(String(document.issued_at));
    numeric(base, document.type === "DT" ? "returns" : "invoices", 1n);
    if (document.type === "MR") numeric(base, "tailoring", 1n);
    const addLine = (
      row: Row,
      employee: string,
      name: string,
      product: string,
      q: bigint,
      revenue: bigint,
      cost: bigint,
    ) => {
      const delta = group(String(document.issued_at)),
        size = String(row.size),
        sizeId = sizeKey(size);
      for (const [key, value] of [
        ["quantity", q],
        ["revenue", revenue],
        ["cost", cost],
      ] as const) {
        numeric(delta, key, value);
        numeric(delta, `p|${product}|${key}`, value);
        numeric(delta, `s|${sizeId}|${key}`, value);
        numeric(delta, `e|${employee}|${key}`, value);
      }
      delta.metrics[`label|p|${product}`] = String(row.name);
      delta.metrics[`label|s|${sizeId}`] = size;
      delta.metrics[`label|e|${employee}`] = name;
    };
    for (const l of lines.filter((l) => l.document_id === document.id)) {
      const q = quantity(l);
      addLine(
        l,
        String(document.user_id),
        String(document.employee_name),
        String(variants.get(l.variant_id) ?? l.variant_id),
        q,
        q * money(l.unit_price) - money(l.discount),
        q * money(l.unit_cost),
      );
    }
    for (const r of returns.filter((r) => r.document_id === document.id)) {
      const l = originals.get(r.original_line_id);
      if (!l)
        throw new Error("Thiếu snapshot dòng hàng gốc để tổng hợp báo cáo.");
      const q = quantity(r);
      addLine(
        l,
        String(l.employee_id),
        String(l.employee_name),
        String(l.product_id),
        -q,
        -money(r.credit),
        -q * money(l.unit_cost),
      );
    }
    const documentPayments = payments.filter(
      (p) => p.document_id === document.id,
    );
    for (const p of documentPayments)
      numeric(
        group(String(p.created_at)),
        p.direction === "receive" ? "payment_in" : "payment_out",
        money(p.amount),
      );
    const token = crypto.randomUUID();
    statements.push(
      db
        .prepare("INSERT OR IGNORE INTO report_receipts VALUES(?,?,?,?)")
        .bind(
          actor.store_id,
          document.id,
          JSON.stringify(documentPayments.map((p) => p.id)),
          token,
        ),
    );
    for (const delta of groups.values())
      statements.push(dailyUpsert(db, delta, String(document.id), token));
    for (const payment of incomingPayments.filter(
      (p) => p.document_id === document.id,
    )) {
      const paymentToken = crypto.randomUUID();
      statements.push(
        db
          .prepare(
            "UPDATE report_receipts SET payment_ids_json=json_insert(payment_ids_json,'$[#]',?),last_token=? WHERE store_id=? AND document_id=? AND NOT EXISTS(SELECT 1 FROM json_each(payment_ids_json) WHERE value=?)",
          )
          .bind(
            payment.id,
            paymentToken,
            actor.store_id,
            document.id,
            payment.id,
          ),
      );
      const delta: Delta = {
        ...group(String(payment.created_at)),
        metrics: {},
        overflow: 0,
      };
      numeric(
        delta,
        payment.direction === "receive" ? "payment_in" : "payment_out",
        money(payment.amount),
      );
      statements.push(
        dailyUpsert(db, delta, String(document.id), paymentToken),
      );
    }
  }
  return statements;
}
