import 'dart:convert';

import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/employees/payroll_calculation.dart';

import 'fixtures.dart';

Map<String, Object?> payrollRuleJson() => {
  'base_salary': 10400000,
  'standard_days': 26,
  'commission_bps': 200,
  'bonus_tiers': [
    {'threshold': 1000000, 'amount': 100000},
  ],
};
Future<LocalService> payrollFixture({bool withRun = false}) async {
  final s = await salesFixture();
  await s.db.execute(
    "INSERT INTO employee_store_assignments VALUES('a1','store-cn01','u1','owner',1,'2026-11-15')",
  );
  final rule = CompensationRule.fromJson(payrollRuleJson());
  await s.db.execute(
    'INSERT INTO compensation_versions VALUES(?,?,?,?,?,?,?,?,?,?)',
    [
      'rule1',
      s.storeId,
      s.deviceId,
      'u1',
      'u1',
      '2026-11',
      1,
      null,
      jsonEncode(rule.toJson()),
      s.now,
    ],
  );
  if (withRun) {
    await s.db.execute(
      'INSERT INTO payroll_runs VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        'run1',
        s.storeId,
        s.deviceId,
        'u1',
        'u1',
        'Nguyễn Thị Thanh - Kế toán bán hàng',
        '2026-11-01',
        '2026-12-01',
        'rule1',
        jsonEncode(rule.toJson()),
        jsonEncode({'net_sales': 2000000, 'attendance_units': 52}),
        jsonEncode(
          calculatePayroll(rule: rule, attendanceUnits: 52, netSales: 2000000),
        ),
        0,
        0,
        s.now,
      ],
    );
  }
  return s;
}
