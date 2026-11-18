import type { Actor } from "./auth";
import { reportStores, reportFilter, assertReportCache } from "./reports";
import { ApiError } from "./security";
import { reportLimits } from "./config";
type Row = Record<string, unknown>;
/** Replace buckets changed since baseline in one SQLite read snapshot. */
export async function refreshReports(db: D1Database, actor: Actor, url: URL) {
  const stores = await reportStores(
      db,
      actor,
      url.searchParams.get("store") ?? actor.store_id,
    ),
    scope = JSON.stringify(stores.map((s) => s.id)),
    filter = reportFilter(url);
  await assertReportCache(db, scope);
  const since = url.searchParams.get("since") ?? "";
  if (
    !/^\d{1,16}$/.test(since) ||
    BigInt(since) > BigInt(Number.MAX_SAFE_INTEGER)
  )
    throw new ApiError(400, "Mốc làm mới không hợp lệ.");
  const result = await db
    .prepare(
      `WITH changes AS (
    SELECT store_id,entity_type,payload FROM change_feed WHERE store_id IN (SELECT value FROM json_each(?)) AND server_seq>? AND entity_type IN ('documents','payments') ORDER BY server_seq LIMIT ?),
    affected AS (
      SELECT c.store_id,substr(datetime(json_extract(c.payload,'$.issued_at'),'+7 hours'),1,10) AS day,json_extract(c.payload,'$.school_year') AS school_year,COALESCE(json_extract(json_extract(c.payload,'$.metadata_json'),'$.school_id'),'') AS school_id FROM changes c WHERE c.entity_type='documents' AND json_extract(c.payload,'$.type') IN ('HD','MR','DT')
      UNION SELECT c.store_id,substr(datetime(json_extract(c.payload,'$.created_at'),'+7 hours'),1,10),d.school_year,COALESCE(json_extract(d.metadata_json,'$.school_id'),'') FROM changes c JOIN documents d ON d.store_id=c.store_id AND d.id=json_extract(c.payload,'$.document_id') WHERE c.entity_type='payments'),
    selected AS (SELECT r.* FROM daily_reports r JOIN affected a ON a.store_id=r.store_id AND a.day=r.day AND a.school_year=r.school_year AND a.school_id=r.school_id WHERE r.day>=? AND r.day<=? ${filter.year ? "AND r.school_year=?" : ""} ${filter.school ? "AND r.school_id=?" : ""})
    SELECT 0 AS tag,NULL AS store_id,NULL AS day,NULL AS school_year,NULL AS school_id,'{}' AS metrics_json,0 AS overflow,(SELECT COUNT(*) FROM changes) AS changed_count,strftime('%Y-%m-%dT%H:%M:%fZ','now') AS generated_at
    UNION ALL SELECT 1,store_id,day,school_year,school_id,metrics_json,overflow,0,NULL FROM selected
    ORDER BY tag,day,store_id,school_year,school_id LIMIT ?`,
    )
    .bind(
      scope,
      Number(since),
      reportLimits.refreshEvents + 1,
      filter.from,
      filter.to,
      ...(filter.year ? [filter.year] : []),
      ...(filter.school ? [filter.school] : []),
      reportLimits.refreshRows + 2,
    )
    .all<Row>();
  const meta = result.results[0],
    rows = result.results.slice(1);
  if (
    Number(meta.changed_count) > reportLimits.refreshEvents ||
    rows.length > reportLimits.refreshRows
  )
    throw new ApiError(
      409,
      "Đang đồng bộ nhiều dữ liệu. Tải lại báo cáo để lấy mốc mới.",
      "REPORT_CHANGED",
    );
  const chunks: string[] = [];
  let bytes = 0;
  for (const row of rows) {
    if (row.overflow === 1)
      throw new ApiError(
        422,
        "Dữ liệu vượt giới hạn tổng hợp cloud; dùng báo cáo cục bộ.",
        "REPORT_OVERFLOW",
      );
    const head = JSON.stringify({
        store_id: row.store_id,
        day: row.day,
        school_year: row.school_year,
        school_id: row.school_id,
      }),
      raw = `${head.slice(0, -1)},"metrics":${row.metrics_json}}`;
    bytes += new TextEncoder().encode(raw).byteLength;
    if (bytes > reportLimits.pageBytes)
      throw new ApiError(
        409,
        "Nhiều nhóm báo cáo vừa thay đổi. Tải lại để lấy mốc mới.",
        "REPORT_CHANGED",
      );
    chunks.push(raw);
  }
  return new Response(
    `{"rows":[${chunks.join(",")}],"generated_at":${JSON.stringify(meta.generated_at)}}`,
    { headers: { "Content-Type": "application/json" } },
  );
}
