import type { Actor } from "./auth";
import { ApiError, checkPermission, text } from "./security";
import { payrollPeriod } from "./payroll";
import { auditStatement } from "./audit";
export async function webPayroll(db: D1Database, actor: Actor, url: URL) {
  checkPermission(actor.role, "payroll", actor.issued_role);
  if (actor.session_kind === "sync")
    throw new ApiError(403, "Phiên nền không được đọc lương.");
  const employee = url.searchParams.get("employee_id");
  if (!employee) {
    const cursor = url.searchParams.get("cursor") ?? "";
    if (cursor.length > 200) throw new ApiError(400, "Cursor không hợp lệ.");
    const result = await db
      .prepare(
        "SELECT u.id,u.display_name,a.active FROM employee_store_assignments a JOIN users u ON u.id=a.user_id WHERE a.store_id=? AND u.id>? ORDER BY u.id LIMIT 201",
      )
      .bind(actor.store_id, cursor)
      .all<Record<string, unknown>>();
    const rows = result.results.slice(0, 200);
    return Response.json({
      employees: rows,
      cursor: rows.at(-1)?.id ?? cursor,
      has_more: result.results.length > 200,
    });
  }
  text(employee, "Nhân viên", 200);
  const period = payrollPeriod(url.searchParams.get("month"));
  const membership = await db
    .prepare(
      "SELECT 1 FROM employee_store_assignments WHERE store_id=? AND user_id=?",
    )
    .bind(actor.store_id, employee)
    .first();
  if (!membership) throw new ApiError(403, "Nhân viên không thuộc cửa hàng.");
  const after = url.searchParams.get("cursor") ?? "";
  if (after.length > 200) throw new ApiError(400, "Cursor không hợp lệ.");
  const results = await db.batch<Record<string, unknown>>([
    db
      .prepare(
        "SELECT p.*,v.reason void_reason,EXISTS(SELECT 1 FROM payroll_reconciliations r WHERE r.store_id=p.store_id AND r.run_id=p.id) needs_reconcile FROM payroll_runs p LEFT JOIN payroll_voids v ON v.store_id=p.store_id AND v.run_id=p.id WHERE p.store_id=? AND p.employee_id=? AND p.period_start=? AND p.id>? ORDER BY p.id LIMIT 21",
      )
      .bind(actor.store_id, employee, period.start, after),
    await auditStatement(
      db,
      actor,
      "PAYROLL_HISTORY_VIEW",
      employee,
      "Xem lịch sử lương online",
      {
        employee_id: employee,
        period_start: period.start,
        period_end: period.end,
      },
    ),
  ]);
  const rows = results[0].results.slice(0, 20);
  return Response.json({
    rows,
    cursor: rows.at(-1)?.id ?? after,
    has_more: results[0].results.length > 20,
    store_id: actor.store_id,
  });
}
