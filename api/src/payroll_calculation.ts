import { ApiError } from "./security";

export interface CompensationRule {
  base_salary: number;
  standard_days: number;
  commission_bps: number;
  bonus_tiers: { threshold: number; amount: number }[];
}
const invalid = () =>
  new ApiError(400, "Cấu hình hoặc dữ liệu tính lương không hợp lệ.");
function integer(
  value: unknown,
  minimum: number,
  maximum = Number.MAX_SAFE_INTEGER,
): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < minimum ||
    value > maximum
  )
    throw invalid();
  return value;
}
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw invalid();
  const row = value as Record<string, unknown>;
  if (
    Object.keys(row).length !== keys.length ||
    keys.some((k) => !Object.hasOwn(row, k))
  )
    throw invalid();
  return row;
}
export function compensationRule(value: unknown): CompensationRule {
  const row = object(value, [
    "base_salary",
    "standard_days",
    "commission_bps",
    "bonus_tiers",
  ]);
  if (!Array.isArray(row.bonus_tiers) || row.bonus_tiers.length > 20)
    throw invalid();
  let previous = -1;
  const bonus_tiers = row.bonus_tiers.map((value) => {
    const tier = object(value, ["threshold", "amount"]);
    const threshold = integer(tier.threshold, 0),
      amount = integer(tier.amount, 0);
    if (threshold <= previous) throw invalid();
    previous = threshold;
    return { threshold, amount };
  });
  return {
    base_salary: integer(row.base_salary, 0),
    standard_days: integer(row.standard_days, 1, 31),
    commission_bps: integer(row.commission_bps, 0, 10000),
    bonus_tiers,
  };
}
export function calculatePayroll(
  value: unknown,
  attendanceUnits: number,
  netSales: number,
) {
  const rule = compensationRule(value);
  integer(attendanceUnits, 0, 62);
  integer(netSales, -Number.MAX_SAFE_INTEGER);
  const standard_units = rule.standard_days * 2;
  const paid_units = Math.min(attendanceUnits, standard_units);
  const eligible_sales = Math.max(netSales, 0);
  let tier_threshold: number | null = null,
    bonus_pay = 0;
  for (const tier of rule.bonus_tiers) {
    if (eligible_sales >= tier.threshold) {
      tier_threshold = tier.threshold;
      bonus_pay = tier.amount;
    }
  }
  const base =
    (BigInt(rule.base_salary) * BigInt(paid_units)) / BigInt(standard_units);
  const commission =
    (BigInt(eligible_sales) * BigInt(rule.commission_bps)) / 10000n;
  const total = base + commission + BigInt(bonus_pay);
  if (total > BigInt(Number.MAX_SAFE_INTEGER))
    throw new ApiError(400, "Tổng lương vượt giới hạn số nguyên VND an toàn.");
  return {
    attendance_units: attendanceUnits,
    paid_units,
    standard_units,
    net_sales: netSales,
    eligible_sales,
    base_pay: Number(base),
    commission_pay: Number(commission),
    bonus_pay,
    tier_threshold,
    total_pay: Number(total),
  };
}
