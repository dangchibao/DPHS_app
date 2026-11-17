import { ApiError, checkPermission, text } from "./security";
import type { Actor } from "./auth";
export type SizeBand = {
  size: string;
  height_min: number;
  height_max: number;
  weight_min: number;
  weight_max: number;
};
export function sizeBands(value: unknown): SizeBand[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 50)
    throw new ApiError(400, "Bảng size cần 1–50 dòng.");
  const sizes = new Set<string>(),
    fields = ["height_min", "height_max", "weight_min", "weight_max"];
  for (const raw of value) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
      throw new ApiError(400, "Dòng size không hợp lệ.");
    const row = raw as Record<string, unknown>;
    if (
      Object.keys(row).length !== 5 ||
      !["size", ...fields].every((k) => k in row)
    )
      throw new ApiError(400, "Cột size không hợp lệ.");
    const size = text(row.size, "Size", 30);
    if (size !== row.size || sizes.has(size))
      throw new ApiError(
        400,
        "Size phải khác nhau và không có khoảng trắng thừa.",
      );
    sizes.add(size);
    for (const field of fields)
      if (
        !Number.isSafeInteger(row[field]) ||
        Number(row[field]) < 1 ||
        Number(row[field]) > 1000000
      )
        throw new ApiError(400, "Số đo phải là số nguyên mm/gram hợp lệ.");
    if (
      Number(row.height_min) > Number(row.height_max) ||
      Number(row.weight_min) > Number(row.weight_max)
    )
      throw new ApiError(400, "Khoảng số đo không hợp lệ.");
  }
  return value as SizeBand[];
}
export function suggestSizes(
  bands: SizeBand[],
  height: number,
  weight: number,
): string[] {
  sizeBands(bands);
  if (
    ![height, weight].every(
      (n) => Number.isSafeInteger(n) && n > 0 && n <= 1000000,
    )
  )
    throw new ApiError(400, "Số đo không hợp lệ.");
  return bands
    .filter(
      (r) =>
        height >= r.height_min &&
        height <= r.height_max &&
        weight >= r.weight_min &&
        weight <= r.weight_max,
    )
    .map((r) => r.size);
}
export async function validateSizeRule(
  db: D1Database,
  actor: Actor,
  row: Record<string, unknown>,
) {
  checkPermission(actor.role, "catalog", actor.issued_role);
  text(row.name, "Tên bảng size");
  const updated = Date.parse(text(row.updated_at, "Ngày sửa"));
  if (
    !Number.isFinite(updated) ||
    updated > Date.now() + 300000 ||
    typeof row.lww_key !== "string" ||
    !row.lww_key.startsWith(`${row.updated_at}|`) ||
    ![0, 1].includes(row.active as number)
  )
    throw new ApiError(400, "Phiên bản bảng size không hợp lệ.");
  let config: unknown;
  try {
    config = JSON.parse(String(row.config_json));
  } catch {
    throw new ApiError(400, "Bảng size không hợp lệ.");
  }
  sizeBands(config);
  if (
    row.product_id !== null &&
    !(await db
      .prepare("SELECT id FROM products WHERE id=?")
      .bind(text(row.product_id, "Sản phẩm"))
      .first())
  )
    throw new ApiError(400, "Sản phẩm không tồn tại hoặc đã ngừng bán.");
}
