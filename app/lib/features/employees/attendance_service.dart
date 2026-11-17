import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';

String workDay(String value) {
  final date = DateTime.tryParse('${value}T00:00:00.000Z');
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      date == null ||
      date.toIso8601String().substring(0, 10) != value) {
    throw ArgumentError('Ngày chấm công không hợp lệ.');
  }
  return value;
}

String daysText(int units) => '${units ~/ 2}${units.isOdd ? ',5' : ''}';

extension AttendanceService on LocalService {
  Future<List<Map<String, Object?>>> attendanceEmployees() {
    require(Permission.attendance);
    return db.rows(
      'SELECT u.id,u.display_name,a.active FROM users u JOIN employee_store_assignments a ON a.user_id=u.id WHERE a.store_id=? ORDER BY u.display_name',
      [storeId],
    );
  }

  Future<bool> attendanceLocked(String employee, String day) async {
    require(Permission.attendance);
    workDay(day);
    return (await db.rows(
      'SELECT p.id FROM payroll_locks p WHERE p.store_id=? AND p.employee_id=? AND p.period_start<=? AND p.period_end>? AND NOT EXISTS(SELECT 1 FROM payroll_lock_releases r WHERE r.store_id=p.store_id AND r.run_id=p.run_id) LIMIT 1',
      [storeId, employee, day, day],
    )).isNotEmpty;
  }

  Future<String> markAttendance({
    required String employeeId,
    required String day,
    required int units,
    required String reason,
  }) async {
    final actor = require(Permission.attendance);
    workDay(day);
    if (![0, 1, 2].contains(units) ||
        reason.trim().isEmpty ||
        reason.length > 200) {
      throw ArgumentError(
        'Công là 0 / 0,5 / 1 ngày và cần lý do tối đa 200 ký tự.',
      );
    }
    return db.transaction(() async {
      final current = require(Permission.attendance);
      if (current.userId != actor.userId) {
        throw StateError('Phiên đã đổi người dùng. Vui lòng thực hiện lại.');
      }
      final created = now,
          id = uuid.v7(),
          today = DateTime.parse(created)
              .add(const Duration(hours: 7))
              .toIso8601String()
              .substring(0, 10);
      if (day.compareTo(today) > 0) {
        throw ArgumentError('Không chấm công cho ngày tương lai.');
      }
      if ((await db.rows(
        'SELECT id FROM employee_store_assignments WHERE store_id=? AND user_id=?',
        [storeId, employeeId],
      )).isEmpty) {
        throw StateError('Nhân viên không thuộc cửa hàng.');
      }
      if (await attendanceLocked(employeeId, day)) {
        throw StateError(
          'Kỳ lương đã chốt; cần đối soát và hủy/chốt lại kỳ có quyền để sửa.',
        );
      }
      await db.execute(
        'INSERT INTO attendance_entries VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          actor.userId,
          employeeId,
          day,
          units,
          reason.trim(),
          created,
          '$created|$deviceId|$id',
        ],
      );
      await audit(
        'ATTENDANCE_MARK',
        'employee',
        employeeId,
        reason: reason.trim(),
        changes: {'entry_id': id, 'work_day': day, 'day_units': units},
      );
      await enqueue('attendance', {'id': id}, 3);
      return id;
    });
  }

  Future<List<Map<String, Object?>>> attendance({
    required String from,
    required String to,
  }) async {
    require(Permission.attendance);
    workDay(from);
    workDay(to);
    if (from.compareTo(to) >= 0) {
      throw ArgumentError('Khoảng ngày chấm công không hợp lệ.');
    }
    final rows = await db.rows(
      '''WITH ranked AS (SELECT a.*,ROW_NUMBER() OVER(PARTITION BY a.employee_id,a.work_day ORDER BY a.lww_key DESC,a.id DESC) AS position
    FROM attendance_entries a WHERE a.store_id=? AND a.work_day>=? AND a.work_day<? AND NOT EXISTS(SELECT 1 FROM attendance_rejections r WHERE r.store_id=a.store_id AND r.id=a.id))
    SELECT a.*,u.display_name,NOT EXISTS(SELECT 1 FROM local_attendance_receipts r WHERE r.store_id=a.store_id AND r.entry_id=a.id) AS pending FROM ranked a JOIN users u ON u.id=a.employee_id WHERE a.position=1 ORDER BY a.work_day DESC,u.display_name''',
      [storeId, from, to],
    );
    for (final row in rows) {
      row['pending'] = row['pending'] == 1;
    }
    return rows;
  }

  Future<List<Map<String, Object?>>> attendanceRejections({
    required String from,
    required String to,
  }) {
    require(Permission.attendance);
    workDay(from);
    workDay(to);
    return db.rows(
      'SELECT r.*,u.display_name FROM attendance_rejections r JOIN users u ON u.id=r.employee_id WHERE r.store_id=? AND r.work_day>=? AND r.work_day<? ORDER BY r.created_at DESC',
      [storeId, from, to],
    );
  }
}
