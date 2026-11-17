import { ApiError, money, text, checkPermission } from "./security";
import type { Actor } from "./auth";
import type { ComboDefinition, ComboSelection } from "./pricing";

export function comboDefinition(row: Record<string, unknown>): ComboDefinition {
  let parts: unknown;
  try {
    parts = JSON.parse(String(row.items_json));
  } catch {
    throw new ApiError(400, "Thành phần combo không hợp lệ.");
  }
  if (!Array.isArray(parts) || parts.length < 1 || parts.length > 20)
    throw new ApiError(400, "Combo cần từ 1 đến 20 thành phần.");
  return {
    id: text(row.id ?? row.combo_id, "ID combo"),
    version: text(row.lww_key ?? row.version, "Phiên bản combo"),
    name: text(row.name, "Tên combo"),
    price: money(row.price),
    parts: parts.map((raw) => {
      if (!raw || typeof raw !== "object" || Array.isArray(raw))
        throw new ApiError(400, "Thành phần combo không hợp lệ.");
      const part = raw as Record<string, unknown>;
      if (
        Object.keys(part).some(
          (k) => !["product_id", "quantity"].includes(k),
        ) ||
        !Number.isSafeInteger(part.quantity) ||
        (part.quantity as number) < 1 ||
        (part.quantity as number) > 100000
      )
        throw new ApiError(400, "Số lượng món trong combo không hợp lệ.");
      return {
        productId: text(part.product_id, "Sản phẩm thành phần"),
        quantity: part.quantity as number,
      };
    }),
  };
}

export async function validateComboRule(
  db: D1Database,
  actor: Actor,
  row: Record<string, unknown>,
) {
  checkPermission(actor.role, "catalog", actor.issued_role);
  if (row.store_id !== actor.store_id)
    throw new ApiError(403, "Combo thuộc cửa hàng khác.");
  const rule = comboDefinition(row);
  const time = Date.parse(text(row.updated_at, "Thời gian"));
  if (
    !Number.isFinite(time) ||
    time > Date.now() + 5 * 60000 ||
    !rule.version.startsWith(`${row.updated_at}|`) ||
    (row.active !== 0 && row.active !== 1)
  )
    throw new ApiError(400, "Phiên bản combo không hợp lệ.");
  const ids = [...new Set(rule.parts.map((p) => p.productId))];
  const products = await db
    .prepare(
      `SELECT id FROM products WHERE id IN (${ids.map(() => "?").join(",")})`,
    )
    .bind(...ids)
    .all();
  if (products.results.length !== ids.length)
    throw new ApiError(400, "Sản phẩm trong combo không tồn tại.");
}

export async function loadComboSelections(
  db: D1Database,
  actor: Actor,
  raw: unknown,
  issuedAt: string,
): Promise<ComboSelection[]> {
  if (raw === undefined) return [];
  if (!Array.isArray(raw) || raw.length > 20)
    throw new ApiError(400, "Danh sách combo không hợp lệ.");
  const proofs = raw.map((value) => {
    if (!value || typeof value !== "object" || Array.isArray(value))
      throw new ApiError(400, "Thông tin combo không hợp lệ.");
    const p = value as Record<string, unknown>;
    if (
      Object.keys(p).some(
        (k) => !["rule_id", "version", "picks", "quantity"].includes(k),
      ) ||
      !Array.isArray(p.picks) ||
      p.picks.length > 20 ||
      !Number.isSafeInteger(p.quantity) ||
      (p.quantity as number) < 1 ||
      (p.quantity as number) > 100000
    )
      throw new ApiError(400, "Số lượng hoặc lựa chọn combo không hợp lệ.");
    return {
      id: text(p.rule_id, "ID combo"),
      version: text(p.version, "Phiên bản"),
      picks: p.picks.map((id) => text(id, "Biến thể")),
      quantity: p.quantity as number,
    };
  });
  if (!proofs.length) return [];
  const result = await db.batch(
    proofs.map((p) =>
      db
        .prepare(
          "SELECT * FROM combo_versions WHERE store_id=? AND combo_id=? AND version=?",
        )
        .bind(actor.store_id, p.id, p.version),
    ),
  );
  return proofs.map((p, index) => {
    const row = result[index]?.results?.[0] as
      Record<string, unknown> | undefined;
    if (
      !row ||
      row.active !== 1 ||
      Date.parse(String(row.updated_at)) > Date.parse(issuedAt) + 5 * 60000
    )
      throw new ApiError(
        409,
        "Không xác minh được phiên bản combo đã bán offline.",
        "COMBO_VERSION",
      );
    return { rule: comboDefinition(row), picks: p.picks, quantity: p.quantity };
  });
}
