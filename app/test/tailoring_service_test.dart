import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_service.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_rule.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/debt/debt_service.dart';
import 'package:ngoc_thanh_pos/features/schools/school_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Đơn may chờ transaction qua nửa đêm kiểm lại ngày hẹn và không cấp mã',
    () async {
      final original = await salesFixture();
      addTearDown(original.db.close);
      var clock = DateTime.utc(2026, 11, 15, 16, 59, 59);
      final s = LocalService(original.db, clock: () => clock)
        ..session = original.session;
      final rule = await s.saveTailoringRule(
        name: 'May đo',
        config: TailoringRule.defaults(),
      );
      final entered = Completer<void>(), release = Completer<void>();
      final blocker = s.db.transaction(() async {
        await s.db.rows('SELECT 1');
        entered.complete();
        await release.future;
      });
      await entered.future;
      final job = s.createTailoring(
        items: [const CartItem('v1', 1)],
        ruleId: rule,
        measurements: {
          for (final k in measurementLabels.keys)
            k: k == 'weight' ? 70000 : 1000,
        },
        options: [],
        dueDate: '2026-11-15',
        notes: '',
        customerName: 'Khách',
        phone: '',
        received: 0,
        method: 'cash',
      );
      final assertion = expectLater(job, throwsArgumentError);
      clock = DateTime.utc(2026, 11, 15, 17);
      release.complete();
      await blocker;
      await assertion;
      expect(
        await s.db.rows("SELECT id FROM documents WHERE type='MR'"),
        isEmpty,
      );
      expect(
        await s.db.rows("SELECT * FROM document_counters WHERE type='MR'"),
        isEmpty,
      );
    },
  );
  test(
    'Phiếu may gắn học sinh dùng đúng phụ huynh và giữ lịch sử trường/lớp',
    () async {
      final s = await salesFixture();
      try {
        final school = await s.saveSchool(
              name: 'Trường mẫu',
              level: 'Tiểu học',
            ),
            schoolClass = await s.saveClass(
              schoolId: school,
              name: '2A',
              year: '2026–2027',
            ),
            student = await s.saveStudent(
              classId: schoolClass,
              code: 'HS-MAY',
              name: 'An',
              parentName: 'Phụ huynh An',
            );
        final rule = await s.saveTailoringRule(
          name: 'May theo số đo',
          config: TailoringRule.defaults(),
        );
        final before = (await s.db.rows('SELECT * FROM customers')).length;
        await s.createTailoring(
          items: [const CartItem('v1', 1)],
          ruleId: rule,
          measurements: {
            for (final k in measurementLabels.keys)
              k: k == 'weight' ? 70000 : 1000,
          },
          options: [],
          dueDate: '2026-11-20',
          notes: '',
          customerName: '',
          phone: '',
          received: 0,
          method: 'cash',
          studentId: student,
        );
        expect((await s.db.rows('SELECT * FROM customers')).length, before);
        expect(
          (await s.studentHistory(student)).single['code'],
          startsWith('MR-'),
        );
        expect((await s.debts()).single['name'], 'Phụ huynh An');
      } finally {
        await s.db.close();
      }
    },
  );
  test('Đơn may snapshot phụ thu, không trừ hàng sẵn; đặt cọc và trạng thái append-only', () async {
    final s = await salesFixture();
    final measurements = {
      for (final key in measurementLabels.keys)
        key: key == 'weight' ? 70000 : 1000,
    };
    try {
      final rule = await s.saveTailoringRule(
        name: 'May theo số đo',
        config: {
          ...TailoringRule.defaults(),
          'base_fee': 20000,
          'options': {
            'rush': {'label': 'May gấp', 'amount': 5000},
          },
        },
      );
      Future<SaleResult> create() => s.createTailoring(
        items: [const CartItem('v1', 2)],
        ruleId: rule,
        measurements: measurements,
        options: ['rush'],
        dueDate: '2026-11-20',
        notes: 'Rộng hơn ở vai',
        customerName: 'Phụ huynh may',
        phone: '0900000000',
        received: 50000,
        method: 'cash',
        commandId: 'mr-test',
        expectedTotal: 250000,
      );
      final doc = await create();
      expect(doc.code, 'MR-CN01-A2-20261115-001');
      expect(doc.total, 250000);
      expect(
        (await s.db.rows('SELECT quantity FROM stock_balances'))
            .single['quantity'],
        10,
      );
      expect(
        (await s.db.rows("SELECT * FROM stock_movements WHERE document_id=?", [
          doc.id,
        ])),
        isEmpty,
      );
      expect((await s.debts()).single['balance'], 200000);
      await s.saveTailoringRule(
        id: rule,
        name: 'Bảng mới',
        config: {...TailoringRule.defaults(), 'base_fee': 30000},
      );
      expect((await create()).code, doc.code);
      await expectLater(
        s.advanceTailoring(
          documentId: doc.id,
          nextStatus: 2,
          reason: 'Sai thứ tự',
        ),
        throwsStateError,
      );
      final event = await s.advanceTailoring(
        documentId: doc.id,
        nextStatus: 1,
        reason: 'Chuyển thợ',
        commandId: 'step1',
      );
      expect(
        await s.advanceTailoring(
          documentId: doc.id,
          nextStatus: 1,
          reason: 'Chuyển thợ',
          commandId: 'step1',
        ),
        event,
      );
      await s.advanceTailoring(
        documentId: doc.id,
        nextStatus: 2,
        reason: 'Kiểm tra xong',
      );
      await s.collectDebt(
        documentId: doc.id,
        amount: 200000,
        method: 'bank',
        note: 'Tất toán may',
      );
      await s.advanceTailoring(
        documentId: doc.id,
        nextStatus: 3,
        reason: 'Phụ huynh đã nhận',
      );
      expect((await s.tailoringOrders()).single['status'], 3);
      expect((await s.tailoringOrders()).single['debt'], 0);
      expect((await s.db.rows('SELECT * FROM document_events')).length, 3);
      await expectLater(
        s.advanceTailoring(
          documentId: doc.id,
          nextStatus: 2,
          reason: 'Lùi trạng thái',
        ),
        throwsStateError,
      );
    } finally {
      await s.db.close();
    }
  });
}
