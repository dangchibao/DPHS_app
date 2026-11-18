import type { Actor } from "./auth";
import { ApiError, checkPermission, text, money } from "./security";
import { push, type SyncRecord } from "./sync";
export async function webCatalog(
  db: D1Database,
  actor: Actor,
  url: URL,
  body?: Record<string, unknown>,
) {
  checkPermission(actor.role, "catalog", actor.issued_role);
  if (actor.device_kind !== "web")
    throw new ApiError(
      403,
      "Dùng đồng bộ native để lưu danh mục trên máy bán hàng.",
    );
  if (body) {
    const records = body.records as SyncRecord[];
    if (
      !Array.isArray(records) ||
      records.length < 2 ||
      records.length > 3 ||
      records.some(
        (r) =>
          !r ||
          typeof r !== "object" ||
          !r.row ||
          typeof r.row !== "object" ||
          !["products", "product_variants", "stock_threshold_rules"].includes(
            r.table,
          ),
      )
    )
      throw new ApiError(
        400,
        "Chỉ cập nhật danh mục, không nhận giao dịch kho.",
      );
    const products = records.filter((r) => r.table === "products"),
      variants = records.filter((r) => r.table === "product_variants"),
      thresholds = records.filter((r) => r.table === "stock_threshold_rules");
    if (products.length !== 1 || variants.length !== 1 || thresholds.length > 1)
      throw new ApiError(400, "Cần một sản phẩm và một biến thể.");
    const p = products[0].row,
      v = variants[0].row;
    if (
      v.product_id !== p.id ||
      thresholds.some((r) => r.row.variant_id !== v.id)
    )
      throw new ApiError(400, "Sai liên kết danh mục.");
    for (const key of [
      "name",
      "category",
      "gender",
      "school_level",
      "school_year",
    ])
      text(p[key], key, 160);
    for (const key of ["sku", "size", "color", "unit"]) text(v[key], key, 100);
    if (v.barcode !== null) text(v.barcode, "Mã vạch", 100);
    for (const r of [p, v])
      if (
        ![0, 1].includes(Number(r.active)) ||
        !Number.isSafeInteger(r.version) ||
        Number(r.version) < 1
      )
        throw new ApiError(400, "Trạng thái/phiên bản không hợp lệ.");
    money(v.price);
    money(v.cost);
    const current = await db
      .prepare("SELECT product_id FROM product_variants WHERE id=?")
      .bind(v.id)
      .first<{ product_id: string }>();
    if (current && current.product_id !== p.id)
      throw new ApiError(409, "Không được chuyển biến thể sang sản phẩm khác.");
    const reason = text(body.reason, "Lý do", 200);
    return push(db, actor, {
      mutations: [{ id: body.id, records }],
      catalog_reason: reason,
    });
  }
  const after = url.searchParams.get("cursor") ?? "",
    search = (url.searchParams.get("search") ?? "")
      .trim()
      .toLocaleLowerCase("vi");
  if (after.length > 200 || search.length > 100)
    throw new ApiError(400, "Bộ lọc không hợp lệ.");
  const result = await db
    .prepare(
      `SELECT v.*,p.name,p.category,p.gender,p.school_level,p.school_year,p.image_path,p.active product_active,p.updated_at product_updated_at,p.version product_version,p.lww_key product_lww_key,COALESCE(s.low_stock_threshold,5) low_stock_threshold,COALESCE(b.quantity,0) quantity
    FROM product_variants v JOIN products p ON p.id=v.product_id LEFT JOIN store_variant_settings s ON s.store_id=? AND s.variant_id=v.id LEFT JOIN stock_balances b ON b.store_id=? AND b.variant_id=v.id WHERE v.id>? ORDER BY v.id LIMIT 201`,
    )
    .bind(actor.store_id, actor.store_id, after)
    .all<Record<string, unknown>>();
  const rows: Record<string, unknown>[] = [];
  let scanned = 0,
    cursor = after;
  for (const r of result.results.slice(0, 200)) {
    scanned++;
    cursor = String(r.id);
    if (
      (url.searchParams.get("inactive") === "1" ||
        (r.active === 1 && r.product_active === 1)) &&
      (!search ||
        [r.name, r.sku, r.barcode, r.size, r.color]
          .join(" ")
          .toLocaleLowerCase("vi")
          .includes(search))
    )
      rows.push(r);
    if (rows.length >= 50) break;
  }
  return Response.json({
    rows,
    cursor,
    has_more: scanned < result.results.length,
    store_id: actor.store_id,
  });
}
