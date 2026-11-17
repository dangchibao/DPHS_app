import type { Actor } from "./auth";
import type { SyncRecord } from "./sync";
import { ApiError, checkPermission, text, sha256 } from "./security";
import { utcInstant } from "./reservation_time";
export const attendanceColumns = [
  "id",
  "store_id",
  "device_id",
  "user_id",
  "employee_id",
  "work_day",
  "day_units",
  "reason",
  "created_at",
  "lww_key",
] as const;
export const attendanceFeedTypes = [
  "attendance_entries",
  "attendance_rejections",
  "payroll_locks",
  "payroll_lock_releases",
];
type Row = Record<string, unknown>;
export function validWorkDay(value: unknown): string {
  const day = text(value, "Ngày chấm công", 10);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(day) ||
    !Number.isFinite(Date.parse(`${day}T00:00:00.000Z`)) ||
    new Date(`${day}T00:00:00.000Z`).toISOString().slice(0, 10) !== day
  )
    throw new ApiError(400, "Ngày chấm công không hợp lệ.");
  return day;
}
export async function validateAttendance(
  db: D1Database,
  actor: Actor,
  records: SyncRecord[],
): Promise<Row | null> {
  const entries = records.filter((r) => r.table === "attendance_entries");
  if (!entries.length) return null;
  checkPermission(actor.role, "attendance", actor.issued_role);
  if (entries.length !== 1 || records.length !== 1)
    throw new ApiError(400, "Mỗi mutation chỉ ghi một bản chấm công.");
  const row = entries[0].row,
    day = validWorkDay(row.work_day),
    created = utcInstant(row.created_at, "Thời điểm chấm công");
  if (
    row.store_id !== actor.store_id ||
    row.device_id !== actor.device_id ||
    row.user_id !== actor.user_id
  )
    throw new ApiError(403, "Chấm công sai cửa hàng/máy/người lập.");
  if (
    created > Date.now() + 300000 ||
    day > new Date(created + 7 * 3600000).toISOString().slice(0, 10) ||
    ![0, 1, 2].includes(row.day_units as number) ||
    row.lww_key !== `${row.created_at}|${actor.device_id}|${row.id}`
  )
    throw new ApiError(
      400,
      "Số ngày công, phiên bản hoặc thời gian không hợp lệ.",
    );
  text(row.reason, "Lý do chấm công", 200);
  text(row.employee_id, "Nhân viên");
  const recordHash = await sha256(
    JSON.stringify(
      Object.fromEntries(attendanceColumns.map((k) => [k, row[k]])),
    ),
  );
  const lookup = await db.batch<Row>([
    db
      .prepare(
        "SELECT id FROM employee_store_assignments WHERE store_id=? AND user_id=?",
      )
      .bind(actor.store_id, row.employee_id),
    db
      .prepare("SELECT id FROM attendance_entries WHERE store_id=? AND id=?")
      .bind(actor.store_id, row.id),
    db
      .prepare("SELECT * FROM attendance_rejections WHERE store_id=? AND id=?")
      .bind(actor.store_id, row.id),
    db
      .prepare(
        "SELECT p.id FROM payroll_locks p WHERE p.store_id=? AND p.employee_id=? AND p.period_start<=? AND p.period_end>? AND NOT EXISTS(SELECT 1 FROM payroll_lock_releases r WHERE r.store_id=p.store_id AND r.run_id=p.run_id) LIMIT 1",
      )
      .bind(actor.store_id, row.employee_id, day, day),
  ]);
  if (!lookup[0].results?.length)
    throw new ApiError(403, "Nhân viên không thuộc cửa hàng.");
  if (lookup[1].results?.length) return null;
  const previous = lookup[2].results?.[0];
  if (previous) {
    if (previous.record_hash !== recordHash)
      throw new ApiError(409, "ID chấm công đã dùng với nội dung khác.");
    return previous;
  }
  if (!lookup[3].results?.length) return null;
  return {
    id: row.id,
    store_id: actor.store_id,
    device_id: actor.device_id,
    user_id: actor.user_id,
    employee_id: row.employee_id,
    work_day: day,
    record_hash: recordHash,
    reason:
      "Kỳ lương đã chốt. Cần đối soát và hủy/chốt lại kỳ có quyền để sửa.",
    created_at: new Date().toISOString(),
  };
}
