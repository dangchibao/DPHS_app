import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/core/money.dart';
import 'package:ngoc_thanh_pos/features/employees/payroll_service.dart';
import 'package:ngoc_thanh_pos/features/employees/payroll_calculation.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/returns/return_service.dart';
import 'package:ngoc_thanh_pos/features/returns/return_pricing.dart';

import 'payroll_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Bảng lương kỳ giữ phiếu hủy; định dạng tổng lớn không mất VND',
    () async {
      final s = await payrollFixture(withRun: true);
      addTearDown(s.db.close);
      expect(await s.payrollPeriodTable('2026-11'), hasLength(1));
      await s.db.execute('INSERT INTO payroll_voids VALUES(?,?,?,?,?,?,?)', [
        'void1',
        s.storeId,
        s.deviceId,
        'u1',
        'run1',
        'Đối soát lại',
        s.now,
      ]);
      expect(
        (await s.payrollPeriodTable('2026-11')).single['void_reason'],
        'Đối soát lại',
      );
      expect(await s.payrollPeriodTable('2026-12'), isEmpty);
      expect(
        formatWholeVnd(BigInt.parse('18014398509481983')),
        '18.014.398.509.481.983 đ',
      );
      expect(formatWholeVnd(BigInt.from(-1000)), '-1.000 đ');
    },
  );
  test('Cấu hình offline có intent/audit/outbox atomic và không rò số lương vào audit', () async {
    final s = await payrollFixture();
    addTearDown(s.db.close);
    final id = await s.saveCompensation(
      employee: 'u1',
      month: '2026-12',
      rule: CompensationRule.fromJson(payrollRuleJson()),
    );
    final command = (await s.db.rows(
      'SELECT * FROM payroll_commands WHERE id=?',
      [id],
    )).single;
    expect(
      (jsonDecode(command['payload_json'] as String) as Map)['config'],
      payrollRuleJson(),
    );
    expect(
      await s.db.rows('SELECT * FROM compensation_versions'),
      hasLength(1),
    );
    final queue = await s.db.rows(
      "SELECT * FROM outbox WHERE entity_type='payroll_command'",
    );
    expect(queue, hasLength(1));
    expect(
      jsonDecode(queue.single['payload'] as String).single['table'],
      'payroll_commands',
    );
    expect(
      jsonEncode(await s.db.rows('SELECT * FROM audit_logs')),
      isNot(contains('10400000')),
    );
    final before = await s.db.rows('SELECT id FROM audit_logs');
    await s.db.execute(
      "CREATE TRIGGER fail_payroll_outbox BEFORE INSERT ON outbox WHEN NEW.entity_type='payroll_command' BEGIN SELECT RAISE(ABORT,'injected_failure'); END;",
    );
    await expectLater(
      s.saveCompensation(
        employee: 'u1',
        month: '2027-01',
        rule: CompensationRule.fromJson(payrollRuleJson()),
      ),
      throwsA(isA<Exception>()),
    );
    expect(await s.db.rows('SELECT id FROM payroll_commands'), hasLength(1));
    expect(await s.db.rows('SELECT id FROM audit_logs'), before);
  });
  test(
    'Quyền lương, restore, ngày kỳ và nguồn mới chặn thao tác nhạy cảm',
    () async {
      final s = await payrollFixture();
      addTearDown(s.db.close);
      final owner = s.session!;
      for (final role in [Role.manager, Role.cashier, Role.warehouse]) {
        s.session = LocalSession(
          userId: owner.userId,
          name: owner.name,
          role: role,
          storeId: owner.storeId,
          deviceId: owner.deviceId,
          expiresAt: owner.expiresAt,
        );
        expect(() => s.payrollHistory('u1'), throwsStateError);
        await expectLater(
          s.saveCompensation(
            employee: 'u1',
            month: '2026-11',
            rule: CompensationRule.fromJson(payrollRuleJson()),
          ),
          throwsStateError,
        );
      }
      s.session = owner;
      s.restoreBlocked = true;
      expect(() => s.payrollEmployees(), throwsStateError);
      s.restoreBlocked = false;
      for (final month in ['2026-00', '2026-13', '26-11', '1999-12']) {
        expect(() => payrollPeriod(month), throwsArgumentError);
      }
      expect(payrollPeriod('2028-02'), ('2028-02-01', '2028-03-01'));
      await expectLater(s.previewPayroll('u1', '2026-11'), throwsStateError);
      await expectLater(
        s.queuePayroll('issue', {'employee_id': 'u1'}),
        throwsStateError,
      );
    },
  );
  test('Doanh số native dùng giá sau giảm và credit gốc; DT tổng 1đ không thành doanh số', () async {
    final s = await payrollFixture();
    addTearDown(s.db.close);
    final sale = await s.sell(
      items: [const CartItem('v1', 2)],
      discount: 1,
      received: 200000,
      method: 'cash',
    );
    final line = (await s.returnableLines(sale.id)).single['id'] as String;
    await s.db.execute(
      "INSERT INTO users VALUES('u2','manager','Quản lý','hash','salt',1,0,'2026-11-15')",
    );
    final owner = s.session!;
    s.session = LocalSession(
      userId: 'u2',
      name: 'Quản lý',
      role: Role.manager,
      storeId: owner.storeId,
      deviceId: owner.deviceId,
      expiresAt: owner.expiresAt,
    );
    final result = await s.createReturn(
      originalId: sale.id,
      items: [ReturnSelection(line, 1)],
      replacements: [const ReplacementSelection('v1', 1)],
      reason: 'Đổi mẫu',
      received: 1,
      method: 'cash',
    );
    expect(
      (await s.db.rows('SELECT total FROM documents WHERE id=?', [
        result.id,
      ])).single['total'],
      1,
    );
    final rows = await s.db.rows(
      'SELECT employee_id,SUM(net_amount) AS net FROM payroll_sales_source WHERE store_id=? GROUP BY employee_id ORDER BY employee_id',
      [s.storeId],
    );
    expect(rows, [
      {'employee_id': 'u1', 'net': 100000},
      {'employee_id': 'u2', 'net': 100000},
    ]);
  });
}
