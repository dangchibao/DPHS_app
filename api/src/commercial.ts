import { ApiError, money, text, checkPermission } from "./security";
import type { Actor } from "./auth";
import type { PricedItem } from "./pricing";

export type Rule = {
  id: string;
  version: string;
  name: string;
  kind: string;
  config: Config;
};
export type Config = {
  school_id: string | null;
  customer_kind: string | null;
  starts_at: string | null;
  ends_at: string | null;
  min_total: number;
  min_quantity: number;
  allow_combo: boolean;
  allow_price_list: boolean;
  prices: Record<string, number>;
  discount_type: string;
  value: number;
  voucher: string;
};
export function parseRule(row: Record<string, unknown>): Rule {
  let raw: unknown;
  try {
    raw = JSON.parse(String(row.config_json));
  } catch {
    throw new ApiError(400, "Cấu hình giá không phải JSON hợp lệ.");
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw))
    throw new ApiError(400, "Cấu hình giá không hợp lệ.");
  const c = raw as Config;
  const keys = [
    "school_id",
    "customer_kind",
    "starts_at",
    "ends_at",
    "min_total",
    "min_quantity",
    "allow_combo",
    "allow_price_list",
    "prices",
    "discount_type",
    "value",
    "voucher",
  ];
  if (
    Object.keys(c).length !== keys.length ||
    Object.keys(c).some((k) => !keys.includes(k)) ||
    !["price_list", "promotion"].includes(String(row.kind)) ||
    (c.school_id !== null &&
      (typeof c.school_id !== "string" || !c.school_id.trim())) ||
    (c.customer_kind !== null &&
      !["parent", "school", "dealer"].includes(c.customer_kind)) ||
    !Number.isSafeInteger(c.min_quantity) ||
    c.min_quantity < 1 ||
    c.min_quantity > 100000 ||
    typeof c.allow_combo !== "boolean" ||
    typeof c.allow_price_list !== "boolean" ||
    !c.prices ||
    typeof c.prices !== "object" ||
    Array.isArray(c.prices) ||
    typeof c.voucher !== "string" ||
    !/^[A-Z0-9_-]{0,32}$/.test(c.voucher)
  )
    throw new ApiError(400, "Điều kiện giá không hợp lệ.");
  money(c.min_total);
  money(c.value);
  for (const date of [c.starts_at, c.ends_at]) {
    if (
      date !== null &&
      (typeof date !== "string" ||
        !Number.isFinite(Date.parse(date)) ||
        new Date(date).toISOString() !== date)
    )
      throw new ApiError(400, "Ngày áp dụng phải là UTC ISO hợp lệ.");
  }
  if (c.starts_at && c.ends_at && c.starts_at >= c.ends_at)
    throw new ApiError(400, "Ngày kết thúc phải sau ngày bắt đầu.");
  if (Object.keys(c.prices).length > 100)
    throw new ApiError(400, "Một bảng giá tối đa 100 biến thể.");
  for (const [variant, price] of Object.entries(c.prices)) {
    text(variant, "Biến thể");
    money(price);
  }
  if (row.kind === "price_list") {
    if (
      !Object.keys(c.prices).length ||
      c.value !== 0 ||
      c.discount_type !== "none" ||
      c.voucher !== "" ||
      c.allow_price_list
    )
      throw new ApiError(400, "Bảng giá không hợp lệ.");
  } else if (
    Object.keys(c.prices).length ||
    !["fixed", "percent"].includes(c.discount_type) ||
    c.value < 1 ||
    (c.discount_type === "percent" && c.value > 10000)
  )
    throw new ApiError(400, "Khuyến mãi không hợp lệ.");
  return {
    id: text(row.id ?? row.rule_id, "ID quy tắc"),
    version: text(row.lww_key ?? row.version, "Phiên bản"),
    name: text(row.name, "Tên"),
    kind: String(row.kind),
    config: c,
  };
}
export function eligible(
  rule: Rule,
  context: {
    school: unknown;
    customerKind: unknown;
    issuedAt: string;
    quantity: number;
    amount: number;
    combos: boolean;
  },
  voucher = "",
) {
  const c = rule.config,
    time = Date.parse(context.issuedAt);
  if (
    !Number.isFinite(time) ||
    (c.starts_at && time < Date.parse(c.starts_at)) ||
    (c.ends_at && time >= Date.parse(c.ends_at)) ||
    (c.school_id && c.school_id !== context.school) ||
    (c.customer_kind && c.customer_kind !== context.customerKind) ||
    context.quantity < c.min_quantity ||
    context.amount < c.min_total ||
    (context.combos && !c.allow_combo) ||
    c.voucher !== voucher.trim().toUpperCase()
  )
    throw new ApiError(
      409,
      "Đơn chưa đủ điều kiện hoặc ưu đãi không được kết hợp.",
      "RULE_CONDITION",
    );
}
export function priceListItems(
  rule: Rule | null,
  items: PricedItem[],
): PricedItem[] {
  return items.map((item) => ({
    ...item,
    price: rule?.config.prices[item.id] ?? item.price,
  }));
}
export function promotionDiscount(
  rule: Rule | null,
  amount: number,
  manual: number,
  hasPriceList: boolean,
): number {
  if (!rule) return 0;
  if (manual !== 0 || (hasPriceList && !rule.config.allow_price_list))
    throw new ApiError(
      409,
      "Khuyến mãi không cộng với giảm thủ công hoặc bảng giá này.",
    );
  return rule.config.discount_type === "fixed"
    ? Math.min(amount, rule.config.value)
    : Number((BigInt(amount) * BigInt(rule.config.value)) / 10000n);
}
export async function validateCommercialRule(
  db: D1Database,
  actor: Actor,
  row: Record<string, unknown>,
) {
  checkPermission(actor.role, "catalog", actor.issued_role);
  const rule = parseRule(row),
    time = Date.parse(String(row.updated_at));
  if (
    row.store_id !== actor.store_id ||
    !Number.isFinite(time) ||
    time > Date.now() + 300000 ||
    !rule.version.startsWith(`${row.updated_at}|`) ||
    (row.active !== 0 && row.active !== 1)
  )
    throw new ApiError(400, "Phiên bản quy tắc giá không hợp lệ.");
  if (
    rule.config.school_id &&
    !(await db
      .prepare("SELECT id FROM schools WHERE store_id=? AND id=?")
      .bind(actor.store_id, rule.config.school_id)
      .first())
  )
    throw new ApiError(403, "Trường khác cửa hàng.");
  const variants = Object.keys(rule.config.prices);
  // D1 Free giới hạn 100 bind/query, chia các danh sách lớn thành tối đa 50 ID.
  for (let i = 0; i < variants.length; i += 50) {
    const part = variants.slice(i, i + 50),
      result = await db
        .prepare(
          `SELECT id FROM product_variants WHERE id IN (${part.map(() => "?").join(",")})`,
        )
        .bind(...part)
        .all();
    if (result.results.length !== part.length)
      throw new ApiError(400, "Biến thể trong bảng giá không tồn tại.");
  }
}
export async function loadCommercialRule(
  db: D1Database,
  actor: Actor,
  raw: unknown,
  kind: string,
  issuedAt: string,
): Promise<Rule | null> {
  if (raw == null) return null;
  if (typeof raw !== "object" || Array.isArray(raw))
    throw new ApiError(400, "Tham chiếu quy tắc không hợp lệ.");
  const ref = raw as Record<string, unknown>;
  if (Object.keys(ref).some((k) => !["id", "version"].includes(k)))
    throw new ApiError(400, "Tham chiếu giá thừa trường.");
  const row = await db
    .prepare(
      "SELECT * FROM commercial_versions WHERE store_id=? AND rule_id=? AND version=?",
    )
    .bind(actor.store_id, text(ref.id, "ID"), text(ref.version, "Phiên bản"))
    .first<Record<string, unknown>>();
  if (
    !row ||
    row.active !== 1 ||
    row.kind !== kind ||
    Date.parse(String(row.updated_at)) > Date.parse(issuedAt) + 300000
  )
    throw new ApiError(
      409,
      "Không xác minh được phiên bản giá offline.",
      "COMMERCIAL_VERSION",
    );
  return parseRule(row);
}
