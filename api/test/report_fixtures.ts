import { testDatabase } from "./database";
import { reportProjection } from "../src/report_projection";
import type { SyncRecord } from "../src/sync";
import type { Actor } from "../src/auth";
const stamp = "2026-11-15T00:00:00.000Z";
export const actor: Actor = {
  store_id: "s1",
  device_id: "d1",
  user_id: "u1",
  name: "Chủ",
  role: "owner",
  issued_role: "owner",
  session_id: "session",
};
export function fixture() {
  const d = testDatabase();
  d.sqlite.exec(
    `INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'${stamp}'); INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','${stamp}'); INSERT INTO users VALUES('u1','owner','Chủ','hash','salt',1,0,'${stamp}'),('u2','staff','Thu ngân','hash','salt',1,0,'${stamp}'); INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES('p1','Áo','Áo sơ mi','Unisex','Tiểu học','2026–2027','${stamp}'); INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES('v1','p1','SKU','M','Trắng','cái',50000,100000,'${stamp}');`,
  );
  return d;
}
export function sale(id = "hd", quantity = 2, cost = 50000): SyncRecord[] {
  return [
    {
      table: "documents",
      row: {
        id,
        store_id: "s1",
        device_id: "d1",
        type: "HD",
        kind: "sale",
        code: `HD-${id}`,
        issued_at: stamp,
        user_id: "u1",
        customer_id: null,
        original_id: null,
        subtotal: quantity * 100000,
        discount: 0,
        total: quantity * 100000,
        school_year: "2026–2027",
        metadata_json: "{}",
      },
    },
    {
      table: "invoice_lines",
      row: {
        id: `${id}-line`,
        store_id: "s1",
        document_id: id,
        variant_id: "v1",
        name: "Áo",
        size: "M",
        color: "Trắng",
        unit: "cái",
        quantity,
        unit_price: 100000,
        unit_cost: cost,
        discount: 0,
        price_version: "",
      },
    },
    {
      table: "payments",
      row: {
        id: `${id}-pay`,
        store_id: "s1",
        device_id: "d1",
        document_id: id,
        user_id: "u1",
        amount: 100000,
        method: "cash",
        direction: "receive",
        created_at: stamp,
        note: "Đặt cọc",
      },
    },
  ];
}
export async function apply(
  d: ReturnType<typeof fixture>,
  records: SyncRecord[],
  user = actor,
) {
  const projection = await reportProjection(d.db, user, records);
  const ledger = records.map((r) =>
    d.db
      .prepare(
        `INSERT OR IGNORE INTO ${r.table} (${Object.keys(r.row).join(",")}) VALUES (${Object.keys(
          r.row,
        )
          .map(() => "?")
          .join(",")})`,
      )
      .bind(...Object.values(r.row)),
  );
  await d.db.batch([...ledger, ...projection]);
}
export function metrics(d: ReturnType<typeof fixture>) {
  return JSON.parse(
    d.sqlite.prepare("SELECT metrics_json FROM daily_reports").get()
      ?.metrics_json as string,
  ) as Record<string, string>;
}
