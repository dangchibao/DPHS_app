import type { Actor } from "./auth";
import { ApiError, checkPermission } from "./security";
import { reportFilter } from "./reports";
type Row = Record<string, unknown>;
export async function auditRead(db: D1Database, actor: Actor, url: URL) {
  checkPermission(actor.role, "audit", actor.issued_role);
  const owner =
    actor.role === "owner" && (actor.issued_role ?? actor.role) === "owner";
  const target =
    url.pathname.endsWith("/options") && owner
      ? "all"
      : (url.searchParams.get("store") ?? actor.store_id);
  if (!owner && target !== actor.store_id)
    throw new ApiError(403, "Chỉ chủ hệ thống được xem nhật ký cửa hàng khác.");
  const stores = await (
    target === "all"
      ? db.prepare("SELECT id,code,name FROM stores ORDER BY id")
      : db.prepare("SELECT id,code,name FROM stores WHERE id=?").bind(target)
  ).all<Row>();
  if (!stores.results.length)
    throw new ApiError(404, "Không tìm thấy cửa hàng.");
  if (url.pathname.endsWith("/options"))
    return Response.json({ stores: stores.results, can_all_stores: owner });
  const filter = reportFilter(url);
  if ((Date.parse(filter.to) - Date.parse(filter.from)) / 86400000 > 30)
    throw new ApiError(400, "Mỗi lần xem nhật ký tối đa 31 ngày.");
  let cursor: unknown = ["", "", ""];
  try {
    if (url.searchParams.has("cursor"))
      cursor = JSON.parse(url.searchParams.get("cursor")!);
  } catch {
    throw new ApiError(400, "Cursor nhật ký không hợp lệ.");
  }
  if (
    !Array.isArray(cursor) ||
    cursor.length !== 3 ||
    cursor.some((x) => typeof x !== "string" || x.length > 200)
  )
    throw new ApiError(400, "Cursor nhật ký không hợp lệ.");
  const match: Record<string, string> = {};
  for (const name of [
    "user_id",
    "device_id",
    "action",
    "entity_id",
    "severity",
  ]) {
    const value = (url.searchParams.get(name) ?? "").trim();
    if (value.length > 200) throw new ApiError(400, "Bộ lọc quá dài.");
    if (value) match[name] = value;
  }
  const result = await db
    .prepare(
      "SELECT * FROM audit_logs WHERE store_id IN (SELECT value FROM json_each(?)) AND client_time>=? AND client_time<? AND (store_id,client_time,id)>(?,?,?) ORDER BY store_id,client_time,id LIMIT 201",
    )
    .bind(
      JSON.stringify(stores.results.map((s) => s.id)),
      filter.fromUtc,
      filter.toUtc,
      ...cursor,
    )
    .all<Row>();
  const rows: Row[] = [];
  let examined = 0,
    bytes = 0,
    after = cursor as string[];
  for (const row of result.results.slice(0, 200)) {
    const matches = Object.entries(match).every(([k, v]) => row[k] === v);
    const size = matches
      ? new TextEncoder().encode(JSON.stringify(row)).length
      : 0;
    if (matches && rows.length && bytes + size > 500000) break;
    examined++;
    after = [String(row.store_id), String(row.client_time), String(row.id)];
    if (matches) {
      rows.push(row);
      bytes += size;
    }
    if (rows.length >= 50) break;
  }
  return Response.json({
    rows,
    cursor: JSON.stringify(after),
    has_more: examined < result.results.length,
    scanned: examined,
    order: "store_time_id",
    can_all_stores: owner,
  });
}
