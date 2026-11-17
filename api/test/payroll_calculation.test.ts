import { expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { calculatePayroll, compensationRule } from "../src/payroll_calculation";
const vectors = JSON.parse(
  readFileSync("../docs/test-vectors/payroll.json", "utf8"),
) as {
  name: string;
  rule: unknown;
  attendance_units: number;
  net_sales: number;
  expected: unknown;
}[];
for (const v of vectors)
  it(v.name, () =>
    expect(calculatePayroll(v.rule, v.attendance_units, v.net_sales)).toEqual(
      v.expected,
    ),
  );
const base = {
  base_salary: 10000000,
  standard_days: 26,
  commission_bps: 200,
  bonus_tiers: [],
};
it("Không nhận cấu hình thiếu, số lẻ, ngưỡng trùng/giảm hoặc input ngoài giới hạn", () => {
  for (const rule of [
    null,
    {},
    { ...base, base_salary: "100" },
    { ...base, base_salary: -1 },
    { ...base, standard_days: 0 },
    { ...base, standard_days: 32 },
    { ...base, commission_bps: 10001 },
    {
      ...base,
      bonus_tiers: [
        { threshold: 2, amount: 1 },
        { threshold: 2, amount: 3 },
      ],
    },
    {
      ...base,
      bonus_tiers: [
        { threshold: 2, amount: 1 },
        { threshold: 1, amount: 3 },
      ],
    },
    { ...base, bonus_tiers: [{ threshold: 1, amount: 1.5 }] },
    { ...base, extra: 1 },
  ])
    expect(() => compensationRule(rule)).toThrow();
  for (const [units, sales] of [
    [-1, 0],
    [1.5, 0],
    [63, 0],
    [1, 1.5],
    [1, Number.MAX_SAFE_INTEGER + 1],
  ])
    expect(() => calculatePayroll(base, units, sales)).toThrow();
});
it("Tổng lương vượt giới hạn bị từ chối thay vì làm tròn sai", () => {
  expect(() =>
    calculatePayroll(
      { ...base, base_salary: Number.MAX_SAFE_INTEGER },
      52,
      Number.MAX_SAFE_INTEGER,
    ),
  ).toThrow();
});
