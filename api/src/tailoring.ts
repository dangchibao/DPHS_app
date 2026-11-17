import { ApiError, money, text, checkPermission } from "./security";
import type { Actor } from "./auth";
import type { PricedItem } from "./pricing";
import type { SyncRecord } from "./sync";

export const measurementFields = [
  "chest",
  "waist",
  "hips",
  "shirt_length",
  "trousers_length",
  "shoulder",
  "height",
  "weight",
] as const;
type Rate = { threshold: number; step: number; amount: number };
export type TailorConfig = {
  base_fee: number;
  rates: Record<string, Rate>;
  options: Record<string, { label: string; amount: number }>;
};
function object(raw: unknown): Record<string, unknown> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw))
    throw new ApiError(400, "Cấu hình/số đo may không hợp lệ.");
  return raw as Record<string, unknown>;
}
export function parseTailorConfig(raw: unknown): TailorConfig {
  const c = object(raw);
  if (
    Object.keys(c).length !== 3 ||
    !["base_fee", "rates", "options"].every((k) => k in c)
  )
    throw new ApiError(400, "Cấu hình phụ thu không hợp lệ.");
  money(c.base_fee);
  const rates = object(c.rates),
    options = object(c.options);
  for (const [field, rawRate] of Object.entries(rates)) {
    const r = object(rawRate);
    if (
      !measurementFields.includes(
        field as (typeof measurementFields)[number],
      ) ||
      Object.keys(r).length !== 3 ||
      !["threshold", "step", "amount"].every((k) => k in r) ||
      !Number.isSafeInteger(r.threshold) ||
      Number(r.threshold) < 0 ||
      Number(r.threshold) > 1000000 ||
      !Number.isSafeInteger(r.step) ||
      Number(r.step) < 1 ||
      Number(r.step) > 1000000
    )
      throw new ApiError(400, "Bậc phụ thu số đo không hợp lệ.");
    money(r.amount);
  }
  if (Object.keys(options).length > 20)
    throw new ApiError(400, "Tối đa 20 yêu cầu có phụ thu.");
  for (const [key, rawOption] of Object.entries(options)) {
    const option = object(rawOption);
    if (!/^[a-zA-Z0-9_-]{1,64}$/.test(key) || Object.keys(option).length !== 2)
      throw new ApiError(400, "Yêu cầu may không hợp lệ.");
    text(option.label, "Tên yêu cầu");
    money(option.amount);
  }
  return c as TailorConfig;
}
export function tailorFee(
  config: TailorConfig,
  raw: unknown,
  selected: unknown,
): number {
  const measurements = object(raw);
  if (Object.keys(measurements).length !== 8)
    throw new ApiError(400, "Nhập đủ 8 số đo.");
  for (const field of measurementFields)
    if (
      !Number.isSafeInteger(measurements[field]) ||
      Number(measurements[field]) < 1 ||
      Number(measurements[field]) > 1000000
    )
      throw new ApiError(400, "Số đo phải dương, theo mm/g.");
  if (
    !Array.isArray(selected) ||
    selected.length > 20 ||
    new Set(selected).size !== selected.length ||
    selected.some(
      (k) => typeof k !== "string" || !Object.hasOwn(config.options, k),
    )
  )
    throw new ApiError(400, "Yêu cầu may đã chọn không hợp lệ.");
  let amount = BigInt(config.base_fee);
  for (const [field, rate] of Object.entries(config.rates)) {
    const excess = Math.max(0, Number(measurements[field]) - rate.threshold);
    amount +=
      ((BigInt(excess) + BigInt(rate.step) - 1n) / BigInt(rate.step)) *
      BigInt(rate.amount);
  }
  for (const key of selected) amount += BigInt(config.options[key].amount);
  if (amount > BigInt(Number.MAX_SAFE_INTEGER))
    throw new ApiError(400, "Phụ thu vượt giới hạn tiền.");
  return Number(amount);
}
function configJson(value: unknown): TailorConfig {
  try {
    return parseTailorConfig(JSON.parse(String(value)));
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, "JSON phụ thu không hợp lệ.");
  }
}
export async function validateTailorRule(
  db: D1Database,
  actor: Actor,
  row: Record<string, unknown>,
) {
  checkPermission(actor.role, "catalog", actor.issued_role);
  configJson(row.config_json);
  text(row.name, "Tên bảng phụ thu");
  const time = Date.parse(text(row.updated_at, "Thời gian"));
  if (
    row.store_id !== actor.store_id ||
    !Number.isFinite(time) ||
    time > Date.now() + 300000 ||
    typeof row.lww_key !== "string" ||
    !row.lww_key.startsWith(`${row.updated_at}|`) ||
    (row.active !== 0 && row.active !== 1)
  )
    throw new ApiError(400, "Phiên bản phụ thu không hợp lệ.");
}
export async function tailorPricing(
  db: D1Database,
  actor: Actor,
  raw: unknown,
  issuedAt: string,
  items: PricedItem[],
): Promise<PricedItem[]> {
  if (
    !Number.isFinite(Date.parse(issuedAt)) ||
    Date.parse(issuedAt) > Date.now() + 300000
  )
    throw new ApiError(409, "Ngày nhận may không hợp lệ.", "CLOCK_SKEW");
  const data = object(raw),
    rule = object(data.rule),
    due = text(data.due_date, "Ngày hẹn");
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(due) ||
    !Number.isFinite(Date.parse(`${due}T00:00:00.000Z`)) ||
    new Date(`${due}T00:00:00.000Z`).toISOString().slice(0, 10) !== due ||
    due <
      new Date(Date.parse(issuedAt) + 7 * 3600000).toISOString().slice(0, 10)
  )
    throw new ApiError(400, "Ngày hẹn không hợp lệ.");
  if (typeof data.notes !== "string" || data.notes.length > 4000)
    throw new ApiError(400, "Ghi chú may tối đa 4000 ký tự.");
  const row = await db
    .prepare(
      "SELECT * FROM tailoring_versions WHERE store_id=? AND rule_id=? AND version=?",
    )
    .bind(
      actor.store_id,
      text(rule.id, "Bảng phụ thu"),
      text(rule.version, "Phiên bản"),
    )
    .first<Record<string, unknown>>();
  if (
    !row ||
    row.active !== 1 ||
    Date.parse(String(row.updated_at)) > Date.parse(issuedAt) + 300000
  )
    throw new ApiError(
      409,
      "Không xác minh được bảng phụ thu offline.",
      "TAILORING_VERSION",
    );
  const config = configJson(row.config_json);
  const fee = tailorFee(config, data.measurements, data.options);
  if (data.per_unit_fee !== fee)
    throw new ApiError(400, "Phụ thu may không khớp.");
  if (
    data.rule_name !== row.name ||
    JSON.stringify(data.option_labels) !==
      JSON.stringify(
        (data.options as string[]).map((k) => config.options[k].label),
      )
  )
    throw new ApiError(400, "Snapshot bảng phụ thu/yêu cầu may không khớp.");
  return items.map((item) => {
    const price = BigInt(item.price) + BigInt(fee);
    if (price > BigInt(Number.MAX_SAFE_INTEGER))
      throw new ApiError(400, "Giá may vượt giới hạn tiền.");
    return { ...item, price: Number(price) };
  });
}
export const tailorSteps = [
  "TAILOR_SEWING",
  "TAILOR_READY",
  "TAILOR_DELIVERED",
];
export async function validateTailorEvents(
  db: D1Database,
  actor: Actor,
  records: SyncRecord[],
) {
  const events = records.filter(
    (r) =>
      r.table === "document_events" && String(r.row.type).startsWith("TAILOR_"),
  );
  if (!events.length) return;
  checkPermission(actor.role, "tailoring", actor.issued_role);
  if (
    events.length !== 1 ||
    records.some(
      (r) => r.table !== "document_events" && r.table !== "audit_logs",
    )
  )
    throw new ApiError(400, "Mỗi lần cập nhật may cần một sự kiện riêng.");
  const row = events[0].row;
  if (
    row.user_id !== actor.user_id ||
    row.related_id !== null ||
    !tailorSteps.includes(String(row.type))
  )
    throw new ApiError(403, "Sự kiện may không hợp lệ.");
  text(row.reason, "Lý do / ghi chú");
  const doc = await db
    .prepare(
      "SELECT device_id,issued_at FROM documents WHERE store_id=? AND id=? AND type='MR' AND kind='tailoring'",
    )
    .bind(actor.store_id, row.document_id)
    .first<{ device_id: string; issued_at: string }>();
  const time = Date.parse(text(row.created_at, "Ngày cập nhật"));
  if (!doc || doc.device_id !== actor.device_id)
    throw new ApiError(
      409,
      "Cập nhật may offline trên máy lập phiếu.",
      "TAILOR_DEVICE",
    );
  if (
    !Number.isFinite(time) ||
    time > Date.now() + 300000 ||
    time < Date.parse(doc.issued_at)
  )
    throw new ApiError(400, "Ngày cập nhật may không hợp lệ.");
  // Chống nhảy/lặp bước bằng trigger và unique index trong cùng batch D1.
}
