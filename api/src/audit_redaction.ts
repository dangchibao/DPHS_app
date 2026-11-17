export const auditMask = "[Đã ẩn]";
const sensitive =
  /password|credential|secret|token|salt|hash|salary|payroll|commission|bonus|compensation|payslip|base_pay|net_pay|gross_pay/i;
const privateAction = /^(PAYROLL|SALARY|COMPENSATION|WAGE)_/i;
const safeIds = new Set([
  "employee_id",
  "user_id",
  "period_id",
  "run_id",
  "slip_id",
  "rule_id",
  "command_id",
  "period_start",
  "period_end",
  "effective_month",
  "status",
  "count",
  "active",
  "role",
  "source_id",
]);
export function redactAuditChanges(
  changes: Record<string, unknown>,
  action: string,
): Record<string, unknown> {
  const redact = (value: unknown): unknown => {
    if (Array.isArray(value)) {
      return value.map(redact);
    }
    if (value && typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value).map(([key, v]) => [
          key,
          sensitive.test(key) ? auditMask : redact(v),
        ]),
      );
    }
    return value;
  };
  return Object.fromEntries(
    Object.entries(changes).map(([key, value]) => [
      key,
      privateAction.test(action) && !safeIds.has(key)
        ? auditMask
        : sensitive.test(key)
          ? auditMask
          : redact(value),
    ]),
  );
}
