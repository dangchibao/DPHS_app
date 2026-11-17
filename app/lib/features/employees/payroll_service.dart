import 'dart:convert';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import 'payroll_calculation.dart';

(String, String) payrollPeriod(String month) {
  if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month) ||
      int.parse(month.substring(0, 4)) < 2000 ||
      int.parse(month.substring(0, 4)) > 9998) {
    throw ArgumentError('Kỳ lương dạng YYYY-MM, từ năm 2000.');
  }
  return (
    '$month-01',
    DateTime.utc(
      int.parse(month.substring(0, 4)),
      int.parse(month.substring(5)) + 1,
    ).toIso8601String().substring(0, 10),
  );
}

extension PayrollService on LocalService {
  Future<List<Map<String, Object?>>> payrollPeriodTable(String month) {
    require(Permission.payroll);
    final (start, _) = payrollPeriod(month);
    return db.rows(
      'SELECT p.*,v.reason AS void_reason,EXISTS(SELECT 1 FROM payroll_reconciliations r WHERE r.store_id=p.store_id AND r.run_id=p.id) AS needs_reconcile FROM payroll_runs p LEFT JOIN payroll_voids v ON v.store_id=p.store_id AND v.run_id=p.id WHERE p.store_id=? AND p.period_start=? ORDER BY p.employee_name,p.created_at DESC',
      [storeId, start],
    );
  }

  Future<List<Map<String, Object?>>> payrollEmployees() {
    require(Permission.payroll);
    return db.rows(
      'SELECT u.id,u.display_name,a.active FROM users u JOIN employee_store_assignments a ON a.user_id=u.id WHERE a.store_id=? ORDER BY u.display_name',
      [storeId],
    );
  }

  Future<List<Map<String, Object?>>> compensationVersions(String employee) {
    require(Permission.payroll);
    return db.rows(
      'SELECT * FROM compensation_versions WHERE store_id=? AND employee_id=? ORDER BY effective_month DESC,revision DESC',
      [storeId, employee],
    );
  }

  Future<List<Map<String, Object?>>> payrollHistory(String employee) {
    require(Permission.payroll);
    return db.rows(
      'SELECT p.*,v.reason AS void_reason,v.created_at AS void_at,EXISTS(SELECT 1 FROM payroll_reconciliations r WHERE r.store_id=p.store_id AND r.run_id=p.id) AS needs_reconcile FROM payroll_runs p LEFT JOIN payroll_voids v ON v.store_id=p.store_id AND v.run_id=p.id WHERE p.store_id=? AND p.employee_id=? ORDER BY p.period_start DESC,p.created_at DESC',
      [storeId, employee],
    );
  }

  Future<List<Map<String, Object?>>> payrollCommands() {
    require(Permission.payroll);
    return db.rows(
      "SELECT c.id,c.kind,c.created_at,r.status,r.message,EXISTS(SELECT 1 FROM outbox o,json_each(o.payload) j WHERE o.store_id=c.store_id AND o.entity_type='payroll_command' AND json_extract(j.value,'\$.row.id')=c.id) AS queued FROM payroll_commands c LEFT JOIN payroll_results r ON r.store_id=c.store_id AND r.id=c.id WHERE c.store_id=? ORDER BY c.created_at DESC LIMIT 50",
      [storeId],
    );
  }

  Future<String> queuePayroll(String kind, Map<String, Object?> payload) async {
    final actor = require(Permission.payroll);
    if (!{'rule', 'issue', 'void'}.contains(kind)) {
      throw ArgumentError('Loại yêu cầu không hợp lệ.');
    }
    return db.transaction(() async {
      if (require(Permission.payroll).userId != actor.userId) {
        throw StateError('Phiên đã đổi người dùng.');
      }
      final id = uuid.v7(), time = now;
      if (kind == 'issue' &&
          (await db.rows('SELECT id FROM outbox WHERE store_id=? LIMIT 1', [
            storeId,
          ])).isNotEmpty) {
        throw StateError(
          'Có thay đổi mới chưa đồng bộ. Xem lại dự tính trước khi chốt.',
        );
      }
      if (utf8.encode(jsonEncode(payload)).length > 16000) {
        throw ArgumentError('Yêu cầu lương quá lớn.');
      }
      await db.execute('INSERT INTO payroll_commands VALUES(?,?,?,?,?,?,?)', [
        id,
        storeId,
        deviceId,
        actor.userId,
        kind,
        jsonEncode(payload),
        time,
      ]);
      await audit(
        'PAYROLL_COMMAND_QUEUE',
        'employee',
        payload['employee_id'] as String? ?? id,
        reason: 'Lập yêu cầu lương',
        severity: 'sensitive',
        changes: {
          'command_id': id,
          'employee_id': payload['employee_id'],
          'status': 'pending',
        },
      );
      await enqueue('payroll_command', {'id': id}, 3);
      return id;
    });
  }

  Future<String> saveCompensation({
    required String employee,
    required String month,
    required CompensationRule rule,
    String? previousId,
  }) async {
    require(Permission.payroll);
    payrollPeriod(month);
    if ((await payrollEmployees()).every((e) => e['id'] != employee)) {
      throw ArgumentError('Nhân viên không thuộc cửa hàng.');
    }
    return queuePayroll('rule', {
      'employee_id': employee,
      'effective_month': month,
      'previous_id': previousId,
      'config': rule.toJson(),
    });
  }

  Future<Map<String, Object?>> previewPayroll(
    String employee,
    String month,
  ) async {
    final actor = require(Permission.payroll);
    payrollPeriod(month);
    final engine = syncEngine;
    if (engine == null || engine.api.token == null) {
      throw StateError('Cần đăng nhập cloud để đối soát dự tính lương.');
    }
    await engine.sync();
    if (require(Permission.payroll).userId != actor.userId) {
      throw StateError('Phiên đã thay đổi.');
    }
    if ((await db.rows('SELECT id FROM outbox WHERE store_id=? LIMIT 1', [
      storeId,
    ])).isNotEmpty) {
      throw StateError('Cần gửi hết hàng đợi trước khi xem nguồn lương cloud.');
    }
    final quote = await engine.api.send(
      '/payroll/preview?employee_id=${Uri.encodeQueryComponent(employee)}&month=$month',
    );
    if (require(Permission.payroll).userId != actor.userId) {
      throw StateError('Phiên đã thay đổi.');
    }
    return quote;
  }

  Future<String> issuePayroll(
    Map<String, Object?> quote, {
    required bool confirmed,
  }) {
    require(Permission.payroll);
    if (!confirmed || quote['period_complete'] != true) {
      throw StateError('Cần kết thúc kỳ và xác nhận đã đối soát máy.');
    }
    if (quote['active_run'] != null) {
      throw StateError('Kỳ đã chốt; cần hủy phiếu cũ trước.');
    }
    if ((quote['devices'] as List).any(
      (d) => (d as Map)['checkpoint'] == null,
    )) {
      throw StateError('Còn máy chưa đối soát.');
    }
    return queuePayroll('issue', {
      'employee_id': quote['employee_id'],
      'month': (quote['period_start'] as String).substring(0, 7),
      'quote_hash': quote['quote_hash'],
      'confirm_reconciled': true,
    });
  }

  Future<String> voidPayroll(String runId, String reason) {
    require(Permission.payroll);
    if (reason.trim().isEmpty || reason.length > 200) {
      throw ArgumentError('Cần lý do hủy tối đa 200 ký tự.');
    }
    return queuePayroll('void', {'run_id': runId, 'reason': reason.trim()});
  }
}
