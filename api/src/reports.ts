import type { Actor } from "./auth";
import { ApiError, checkPermission, text } from "./security";
import { reportLimits } from "./config";
import { reportProjection } from "./report_projection";
import { auditStatement } from "./audit";

type Row = Record<string, unknown>;
export async function reportStores(
  db: D1Database,
  actor: Actor,
  requested: unknown = actor.store_id,
) {
  checkPermission(actor.role, "reports", actor.issued_role);
  const target = text(requested, "Cửa hàng");
  const owner =
    actor.role === "owner" && (actor.issued_role ?? actor.role) === "owner";
  if (!owner && target !== actor.store_id)
    throw new ApiError(
      403,
      "Chỉ chủ hệ thống được xem cửa hàng khác/tổng toàn hệ thống.",
    );
  const stores = await (
    target === "all"
      ? db.prepare("SELECT id,code,name FROM stores ORDER BY code")
      : db.prepare("SELECT id,code,name FROM stores WHERE id=?").bind(target)
  ).all<Row>();
  if (!stores.results.length)
    throw new ApiError(404, "Không tìm thấy cửa hàng.");
  return stores.results;
}
function day(value: unknown) {
  const result = text(value, "Ngày báo cáo", 10),
    date = new Date(`${result}T00:00:00.000Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(result) ||
    !Number.isFinite(date.valueOf()) ||
    date.toISOString().slice(0, 10) !== result ||
    date.getUTCFullYear() < 2000 ||
    date.getUTCFullYear() > 9998
  )
    throw new ApiError(400, "Ngày báo cáo dạng YYYY-MM-DD, từ năm 2000.");
  return result;
}
export function reportFilter(url: URL) {
  const from = day(url.searchParams.get("from")),
    to = day(url.searchParams.get("to"));
  const days = (Date.parse(to) - Date.parse(from)) / 86400000 + 1;
  if (days < 1 || days > reportLimits.maxDays)
    throw new ApiError(400, "Báo cáo từ 1 đến 366 ngày.");
  return {
    from,
    to,
    fromUtc: new Date(Date.parse(from) - 7 * 3600000).toISOString(),
    toUtc: new Date(Date.parse(to) + 17 * 3600000).toISOString(),
    year: (url.searchParams.get("year") ?? "").trim(),
    school: (url.searchParams.get("school") ?? "").trim(),
  };
}
function cursor(url: URL, length: number) {
  const raw = url.searchParams.get("cursor");
  if (!raw) return Array<string>(length).fill("");
  if (raw.length > 2000)
    throw new ApiError(400, "Cursor báo cáo không hợp lệ.");
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new ApiError(400, "Cursor báo cáo không hợp lệ.");
  }
  if (
    !Array.isArray(parsed) ||
    parsed.length !== length ||
    parsed.some((v) => typeof v !== "string" || v.length > 300)
  )
    throw new ApiError(400, "Cursor báo cáo không hợp lệ.");
  return parsed as string[];
}
const ids = (stores: Row[]) => JSON.stringify(stores.map((s) => s.id));
async function feedCursor(db: D1Database, scope: string) {
  const row = await db
    .prepare(
      "SELECT CAST(COALESCE(MAX(last_seq),0) AS TEXT) AS cursor FROM (SELECT (SELECT server_seq FROM change_feed WHERE store_id=j.value ORDER BY server_seq DESC LIMIT 1) AS last_seq FROM json_each(?) j)",
    )
    .bind(scope)
    .first<{ cursor: string }>();
  return row!.cursor;
}
export async function reportOptions(db: D1Database, actor: Actor) {
  const owner =
    actor.role === "owner" && (actor.issued_role ?? actor.role) === "owner";
  const stores = await reportStores(db, actor, owner ? "all" : actor.store_id);
  const schools = await db
    .prepare(
      "SELECT id,store_id,name FROM schools WHERE store_id IN (SELECT value FROM json_each(?)) ORDER BY store_id,name",
    )
    .bind(ids(stores))
    .all<Row>();
  return Response.json({
    stores,
    schools: schools.results,
    can_all_stores: owner,
  });
}
export async function assertReportCache(db: D1Database, scope: string) {
  const state = await db
    .prepare(
      "SELECT store_id FROM report_cache_state WHERE store_id IN (SELECT value FROM json_each(?)) AND needs_rebuild=1 LIMIT 1",
    )
    .bind(scope)
    .first();
  if (state)
    throw new ApiError(
      409,
      "Cửa hàng có dữ liệu cũ cần chủ hệ thống chuẩn bị bảng tổng hợp trước khi xem.",
      "REPORT_REBUILD_REQUIRED",
    );
}
export async function reportDaily(db: D1Database, actor: Actor, url: URL) {
  const stores = await reportStores(
      db,
      actor,
      url.searchParams.get("store") ?? actor.store_id,
    ),
    scope = ids(stores),
    filter = reportFilter(url),
    after = cursor(url, 4);
  const startCursor = await feedCursor(db, scope);
  await assertReportCache(db, scope);
  const result = await db
    .prepare(
      `SELECT * FROM daily_reports WHERE store_id IN (SELECT value FROM json_each(?)) AND day>=? AND day<=? ${filter.year ? "AND school_year=?" : ""} ${filter.school ? "AND school_id=?" : ""} AND (day,store_id,school_year,school_id)>(?,?,?,?) ORDER BY day,store_id,school_year,school_id LIMIT ?`,
    )
    .bind(
      scope,
      filter.from,
      filter.to,
      ...(filter.year ? [filter.year] : []),
      ...(filter.school ? [filter.school] : []),
      ...after,
      reportLimits.pageRows + 1,
    )
    .all<Row>();
  const chunks: string[] = [];
  let bytes = 0,
    last: Row | undefined;
  for (const row of result.results.slice(0, reportLimits.pageRows)) {
    if (row.overflow === 1)
      throw new ApiError(
        422,
        "Bảng tổng hợp cloud vượt giới hạn an toàn; dùng báo cáo SQLite tại cửa hàng để giữ chính xác số tiền.",
        "REPORT_OVERFLOW",
      );
    const prefix = JSON.stringify({
      store_id: row.store_id,
      day: row.day,
      school_year: row.school_year,
      school_id: row.school_id,
    });
    const raw = `${prefix.slice(0, -1)},"metrics":${row.metrics_json}}`,
      size = new TextEncoder().encode(raw).byteLength;
    if (bytes + size > reportLimits.pageBytes && chunks.length) break;
    chunks.push(raw);
    bytes += size;
    last = row;
  }
  const more = result.results.length > chunks.length,
    next =
      more && last
        ? JSON.stringify([
            last.day,
            last.store_id,
            last.school_year,
            last.school_id,
          ])
        : null;
  return new Response(
    `{"rows":[${chunks.join(",")}],"next_cursor":${JSON.stringify(next)},"feed_cursor":${JSON.stringify(startCursor)},"stores":${JSON.stringify(stores)}}`,
    { headers: { "Content-Type": "application/json" } },
  );
}
export async function rebuildReports(db: D1Database, actor: Actor, body: Row) {
  checkPermission(actor.role, "configure", actor.issued_role);
  const stores = await reportStores(db, actor, body.store_id ?? actor.store_id);
  if (stores.length !== 1)
    throw new ApiError(400, "Chuẩn bị từng cửa hàng một.");
  const store = String(stores[0].id);
  const missing = await db
    .prepare(
      "SELECT d.* FROM documents d WHERE d.store_id=? AND d.type IN ('HD','MR','DT') AND NOT EXISTS(SELECT 1 FROM report_receipts r WHERE r.store_id=d.store_id AND r.document_id=d.id) ORDER BY d.id LIMIT ?",
    )
    .bind(store, reportLimits.rebuildDocuments)
    .all<Row>();
  const statements = await reportProjection(
    db,
    { ...actor, store_id: store },
    missing.results.map((row) => ({ table: "documents", row })),
  );
  const pending =
    "EXISTS(SELECT 1 FROM documents d WHERE d.store_id=? AND d.type IN ('HD','MR','DT') AND NOT EXISTS(SELECT 1 FROM report_receipts r WHERE r.store_id=d.store_id AND r.document_id=d.id))";
  statements.push(
    db
      .prepare(
        `INSERT INTO report_cache_state VALUES(?,${pending}) ON CONFLICT(store_id) DO UPDATE SET needs_rebuild=excluded.needs_rebuild`,
      )
      .bind(store, store),
  );
  if (missing.results.length)
    statements.push(
      await auditStatement(
        db,
        actor,
        "REPORT_REBUILD",
        store,
        "Chuẩn bị bảng tổng hợp dữ liệu cũ",
        { count: missing.results.length, store_id: store },
      ),
    );
  await db.batch(statements);
  const state = await db
    .prepare("SELECT needs_rebuild FROM report_cache_state WHERE store_id=?")
    .bind(store)
    .first<{ needs_rebuild: number }>();
  return Response.json({
    processed: missing.results.length,
    has_more: state?.needs_rebuild === 1,
  });
}
export async function reportDetails(db: D1Database, actor: Actor, url: URL) {
  const stores = await reportStores(
      db,
      actor,
      url.searchParams.get("store") ?? actor.store_id,
    ),
    scope = ids(stores),
    kind = url.searchParams.get("kind"),
    filter = reportFilter(url),
    after = cursor(url, 2);
  const financial = `d.store_id IN (SELECT value FROM json_each(?)) ${filter.year ? "AND d.school_year=?" : ""} ${filter.school ? "AND json_extract(d.metadata_json,'$.school_id')=?" : ""}`;
  const args = [
    scope,
    ...(filter.year ? [filter.year] : []),
    ...(filter.school ? [filter.school] : []),
  ];
  let result: D1Result<Row>;
  if (kind === "debts") {
    result = await db
      .prepare(
        `SELECT b.store_id,b.document_id AS id,d.code,CAST(b.amount AS TEXT) AS amount,b.due_date,COALESCE(json_extract(d.metadata_json,'$.customer_name'),c.name,'Khách') AS customer_name FROM receivable_report_balances b INDEXED BY receivable_reports_unpaid JOIN documents d ON d.store_id=b.store_id AND d.id=b.document_id LEFT JOIN customers c ON c.store_id=b.store_id AND c.id=b.customer_id WHERE b.amount>0 AND ${financial} AND (b.store_id,b.document_id)>(?,?) ORDER BY b.store_id,b.document_id LIMIT ?`,
      )
      .bind(...args, ...after, reportLimits.pageRows + 1)
      .all<Row>();
  } else if (kind === "tailoring") {
    result = await db
      .prepare(
        `SELECT d.store_id,d.id,d.code,CAST(d.total AS TEXT) AS amount,COALESCE(json_extract(d.metadata_json,'$.customer_name'),'') AS customer_name,json_extract(d.metadata_json,'$.tailoring.due_date') AS due_date,CASE WHEN EXISTS(SELECT 1 FROM document_events e WHERE e.store_id=d.store_id AND e.document_id=d.id AND e.type='TAILOR_DELIVERED' AND e.created_at<?) THEN 3 WHEN EXISTS(SELECT 1 FROM document_events e WHERE e.store_id=d.store_id AND e.document_id=d.id AND e.type='TAILOR_READY' AND e.created_at<?) THEN 2 WHEN EXISTS(SELECT 1 FROM document_events e WHERE e.store_id=d.store_id AND e.document_id=d.id AND e.type='TAILOR_SEWING' AND e.created_at<?) THEN 1 ELSE 0 END AS status FROM documents d WHERE ${financial} AND d.type='MR' AND d.issued_at>=? AND d.issued_at<? AND (d.store_id,d.id)>(?,?) ORDER BY d.store_id,d.id LIMIT ?`,
      )
      .bind(
        filter.toUtc,
        filter.toUtc,
        filter.toUtc,
        ...args,
        filter.fromUtc,
        filter.toUtc,
        ...after,
        reportLimits.pageRows + 1,
      )
      .all<Row>();
  } else if (kind === "stock") {
    const now = new Date().toISOString();
    result = await db
      .prepare(
        `SELECT s.id AS store_id,v.id,v.size,v.color,p.name,CAST(COALESCE(b.quantity,0) AS TEXT) AS quantity,CAST(v.cost AS TEXT) AS unit_cost,CAST(COALESCE((SELECT SUM(r.quantity) FROM reservation_lines r WHERE r.store_id=s.id AND r.variant_id=v.id AND r.created_at<=? AND r.expires_at>? AND NOT EXISTS(SELECT 1 FROM reservation_events e WHERE e.store_id=r.store_id AND e.document_id=r.document_id AND e.created_at<=?)),0) AS TEXT) AS reserved FROM stores s CROSS JOIN product_variants v JOIN products p ON p.id=v.product_id LEFT JOIN stock_balances b ON b.store_id=s.id AND b.variant_id=v.id WHERE s.id IN (SELECT value FROM json_each(?)) ${filter.year ? "AND p.school_year=?" : ""} AND (s.id,v.id)>(?,?) ORDER BY s.id,v.id LIMIT ?`,
      )
      .bind(
        now,
        now,
        now,
        scope,
        ...(filter.year ? [filter.year] : []),
        ...after,
        reportLimits.pageRows + 1,
      )
      .all<Row>();
  } else throw new ApiError(400, "Loại báo cáo không hợp lệ.");
  const rows = result.results.slice(0, reportLimits.pageRows),
    last = rows.at(-1),
    more = result.results.length > rows.length;
  return Response.json({
    rows,
    next_cursor: more && last ? JSON.stringify([last.store_id, last.id]) : null,
    as_of: kind === "debts" || kind === "stock" ? "current" : filter.to,
    generated_at: new Date().toISOString(),
    stores,
  });
}
