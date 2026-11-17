import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/employees/payroll_calculation.dart';

void main() {
  final vectors = jsonDecode(
    File('../docs/test-vectors/payroll.json').readAsStringSync(),
  ) as List;
  for (final v in vectors) {
    test(v['name'] as String, () {
      expect(
        calculatePayroll(
          rule: CompensationRule.fromJson(v['rule']),
          attendanceUnits: v['attendance_units'] as int,
          netSales: v['net_sales'] as int,
        ),
        v['expected'],
      );
    });
  }
  final base = <String, Object?>{
    'base_salary': 10000000,
    'standard_days': 26,
    'commission_bps': 200,
    'bonus_tiers': [],
  };
  test('Không nhận cấu hình thiếu, số lẻ, ngưỡng trùng/giảm hoặc input ngoài giới hạn', () {
    for (final rule in [
      null,
      {},
      {...base, 'base_salary': '100'},
      {...base, 'base_salary': -1},
      {...base, 'standard_days': 0},
      {...base, 'standard_days': 32},
      {...base, 'commission_bps': 10001},
      {
        ...base,
        'bonus_tiers': [
          {'threshold': 2, 'amount': 1},
          {'threshold': 2, 'amount': 3},
        ],
      },
      {
        ...base,
        'bonus_tiers': [
          {'threshold': 2, 'amount': 1},
          {'threshold': 1, 'amount': 3},
        ],
      },
      {
        ...base,
        'bonus_tiers': [
          {'threshold': 1, 'amount': 1.5},
        ],
      },
      {...base, 'extra': 1},
    ]) {
      expect(() => CompensationRule.fromJson(rule), throwsArgumentError);
    }
    for (final (units, sales) in [(-1, 0), (63, 0), (1, 9007199254740992)]) {
      expect(
        () => calculatePayroll(
          rule: CompensationRule.fromJson(base),
          attendanceUnits: units,
          netSales: sales,
        ),
        throwsArgumentError,
      );
    }
  });
  test('Tổng lương vượt giới hạn bị từ chối thay vì làm tròn sai', () {
    expect(
      () => calculatePayroll(
        rule: CompensationRule.fromJson({
          ...base,
          'base_salary': 9007199254740991,
        }),
        attendanceUnits: 52,
        netSales: 9007199254740991,
      ),
      throwsArgumentError,
    );
  });
}
