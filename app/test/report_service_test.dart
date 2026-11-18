import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/reports/report_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/returns/return_service.dart';
import 'package:ngoc_thanh_pos/features/returns/return_pricing.dart';
import 'package:ngoc_thanh_pos/features/debt/debt_service.dart';
import 'package:ngoc_thanh_pos/features/schools/school_service.dart';
import 'package:ngoc_thanh_pos/features/reservations/reservation_service.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_service.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_rule.dart';

import 'payroll_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Lọc trường/năm theo snapshot, giữ hàng chỉ giảm khả dụng; may riêng đúng trạng thái cuối kỳ', () async {
    final source = await payrollFixture();
    addTearDown(source.db.close);
    var clock = source.clock();
    final s = LocalService(source.db, clock: () => clock)
      ..session = source.session;
    final school = await s.saveSchool(name: 'Trường A', level: 'Tiểu học');
    await s.sell(
      items: [const CartItem('v1', 1)],
      discount: 0,
      received: 100000,
      method: 'cash',
      schoolId: school,
    );
    await s.sell(
      items: [const CartItem('v1', 2)],
      discount: 0,
      received: 200000,
      method: 'cash',
    );
    await s.reserveItems(
      [const CartItem('v1', 2)],
      name: 'Khách giữ',
      duration: const Duration(hours: 2),
    );
    final filtered = await s.localReport(
      ReportRange(
        '2026-11-15',
        '2026-11-15',
        schoolId: school,
        year: '2026–2027',
      ),
    );
    expect(filtered.totals['revenue'], BigInt.from(100000));
    expect(filtered.totals['payment_in'], BigInt.from(100000));
    expect(filtered.tables['Tồn kho hiện tại']!.rows.single.sublist(3, 6), [
      7,
      2,
      5,
    ]);
    final rule = await s.saveTailoringRule(
      name: 'May đo',
      config: TailoringRule.defaults(),
    );
    final mr = await s.createTailoring(
      items: [const CartItem('v1', 1)],
      ruleId: rule,
      measurements: {
        for (final k in measurementLabels.keys) k: k == 'weight' ? 70000 : 1000,
      },
      options: [],
      dueDate: '2026-11-20',
      notes: '',
      customerName: 'Khách may',
      phone: '',
      received: 0,
      method: 'cash',
    );
    clock = DateTime.utc(2026, 11, 17);
    await s.advanceTailoring(
      documentId: mr.id,
      nextStatus: 1,
      reason: 'Bắt đầu may',
    );
    final before = await s.localReport(ReportRange('2026-11-15', '2026-11-15'));
    expect(before.tables['Đơn may riêng']!.rows.single[2], '2026-11-20');
    expect(before.tables['Đơn may riêng']!.rows.single[3], 'Mới nhận');
    expect(
      (await s.localReport(ReportRange('2026-11-15', '2026-11-17')))
          .tables['Đơn may riêng']!
          .rows
          .single[3],
      'Đang may',
    );
  });
  test(
    'Phân trang hơn 1000 dòng cùng timestamp không bỏ hoặc đếm trùng',
    () async {
      final s = await payrollFixture();
      addTearDown(s.db.close);
      await s.db.transaction(() async {
        for (var i = 0; i < 1001; i++) {
          final suffix = i.toString().padLeft(4, '0');
          await s.db.execute(
            'INSERT INTO documents VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              'bulk-$suffix',
              s.storeId,
              s.deviceId,
              'HD',
              'sale',
              'HD-bulk-$suffix',
              s.now,
              'u1',
              null,
              null,
              100000,
              0,
              100000,
              '2026–2027',
              '{}',
            ],
          );
          await s.db.execute(
            'INSERT INTO invoice_lines VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              'bulk-line-$suffix',
              s.storeId,
              'bulk-$suffix',
              'v1',
              'Áo',
              'M',
              'Trắng',
              'cái',
              1,
              100000,
              50000,
              0,
              '',
            ],
          );
        }
      });
      final report = await s.localReport(
        ReportRange('2026-11-15', '2026-11-15'),
      );
      expect(report.totals['invoices'], BigInt.from(1001));
      expect(report.totals['revenue'], BigInt.from(100100000));
      expect(report.totals['cost'], BigInt.from(50050000));
      expect(report.tables['Size bán chạy']!.rows.single[1], BigInt.from(1001));
    },
  );
  test(
    'Lãi gộp/giá vốn lớn hơn 2^53 vẫn đúng từng VND và cách ly cửa hàng',
    () async {
      final s = await payrollFixture();
      addTearDown(s.db.close);
      await s.db.execute(
        'UPDATE product_variants SET cost=?,lww_key=? WHERE id=?',
        [
          9007199254740991,
          '2026-11-15T00:00:00.000Z|device-a2|high-cost',
          'v1',
        ],
      );
      await s.sell(
        items: [const CartItem('v1', 2)],
        discount: 0,
        received: 200000,
        method: 'cash',
      );
      await s.db.execute(
        'UPDATE product_variants SET cost=1,lww_key=? WHERE id=?',
        ['2026-11-15T00:00:01.000Z|device-a2|new-cost', 'v1'],
      );
      final report = await s.localReport(
        ReportRange('2026-11-15', '2026-11-15'),
      );
      expect(report.totals['cost'], BigInt.parse('18014398509481982'));
      expect(
        report.totals['gross_profit'],
        BigInt.from(200000) - BigInt.parse('18014398509481982'),
      );
      await s.db.execute(
        "INSERT INTO stores VALUES('s2','NT-CN02','Cửa hàng khác',1,'2026-11-15');",
      );
      await s.db.execute(
        "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d2','s2','B3','Máy khác','approved','2026-11-15')",
      );
      final other =
          LocalService(s.db, storeId: 's2', deviceId: 'd2', clock: s.clock)
            ..session = LocalSession(
              userId: 'u1',
              name: 'Chủ',
              role: Role.owner,
              storeId: 's2',
              deviceId: 'd2',
              expiresAt: DateTime.utc(2027),
            );
      expect(
        (await other.localReport(ReportRange('2026-11-15', '2026-11-15')))
            .totals['revenue'],
        BigInt.zero,
      );
    },
  );
  test(
    'Báo cáo đúng net/giá vốn trả, thu tiền/debt cuối kỳ và không lộ lương',
    () async {
      final s = await payrollFixture();
      addTearDown(s.db.close);
      final sale = await s.sell(
        items: [const CartItem('v1', 2)],
        discount: 1,
        received: 50000,
        method: 'cash',
        customerName: 'Phụ huynh',
      );
      final first = await s.localReport(
        ReportRange('2026-11-15', '2026-11-15'),
      );
      expect(first.totals['revenue'], BigInt.from(199999));
      expect(first.totals['cost'], BigInt.from(100000));
      expect(first.totals['gross_profit'], BigInt.from(99999));
      expect(first.totals['debt'], BigInt.from(149999));
      final line = (await s.returnableLines(sale.id)).single['id'] as String;
      await s.createReturn(
        originalId: sale.id,
        items: [ReturnSelection(line, 1)],
        replacements: [const ReplacementSelection('v1', 1)],
        reason: 'Đổi size',
        received: 0,
        method: 'cash',
      );
      final result = await s.localReport(
        ReportRange('2026-11-15', '2026-11-15'),
      );
      expect(result.totals['revenue'], BigInt.from(200000));
      expect(result.totals['cost'], BigInt.from(100000));
      expect(result.totals['gross_profit'], BigInt.from(100000));
      expect(result.totals['payment_in'], BigInt.from(50000));
      expect(result.totals['debt'], BigInt.from(150000));
      expect(result.totals['invoices'], BigInt.one);
      expect(result.totals['returns'], BigInt.one);
      expect(
        result.tables.keys,
        containsAll([
          'Sản phẩm · lãi gộp',
          'Size bán chạy',
          'Tồn kho hiện tại',
          'Đơn may riêng',
          'Công nợ cuối kỳ',
          'Hiệu suất nhân viên',
        ]),
      );
      expect(result.tables['Tồn kho hiện tại']!.rows.single[3], 8);
      expect(
        result.tables['Hiệu suất nhân viên']!.headers.join(),
        isNot(contains('lương')),
      );
      expect(
        (await s.localReport(
          ReportRange('2026-11-15', '2026-11-15', year: 'không khớp'),
        )).totals['revenue'],
        BigInt.zero,
      );
    },
  );
  test('Thu công nợ sau kỳ không đổi số dư báo cáo kỳ trước', () async {
    final source = await payrollFixture();
    addTearDown(source.db.close);
    var clock = DateTime.utc(2026, 11, 15);
    final s = LocalService(source.db, clock: () => clock)
      ..session = source.session;
    final sale = await s.sell(
      items: [const CartItem('v1', 1)],
      discount: 0,
      received: 20000,
      method: 'cash',
      customerName: 'Khách',
    );
    clock = DateTime.utc(2026, 11, 17);
    await s.collectDebt(
      documentId: sale.id,
      amount: 80000,
      method: 'bank',
      note: 'Trả đủ',
    );
    expect(
      (await s.localReport(ReportRange('2026-11-15', '2026-11-15')))
          .totals['debt'],
      BigInt.from(80000),
    );
    final after = await s.localReport(ReportRange('2026-11-17', '2026-11-17'));
    expect(after.totals['revenue'], BigInt.zero);
    expect(after.totals['payment_in'], BigInt.from(80000));
    expect(after.totals['debt'], BigInt.zero);
  });
  test(
    'Khoanh cửa hàng, quyền, kỳ ngày Việt Nam và Excel giữ nguyên số lớn',
    () async {
      final s = await payrollFixture();
      addTearDown(s.db.close);
      final range = ReportRange('2026-11-15', '2026-11-15');
      expect(range.from, '2026-11-14T17:00:00.000Z');
      expect(range.to, '2026-11-15T17:00:00.000Z');
      for (final days in [
        ('2026-02-30', '2026-03-01'),
        ('2026-11-16', '2026-11-15'),
        ('2025-01-01', '2026-01-02'),
      ]) {
        expect(() => ReportRange(days.$1, days.$2), throwsArgumentError);
      }
      await expectLater(
        s.localReport(range, isCancelled: () => true),
        throwsStateError,
      );
      final owner = s.session!;
      s.session = LocalSession(
        userId: 'u1',
        name: 'Thu ngân',
        role: Role.cashier,
        storeId: s.storeId,
        deviceId: s.deviceId,
        expiresAt: owner.expiresAt,
      );
      await expectLater(s.localReport(range), throwsStateError);
      final table = ReportTable(
        ['Tiền'],
        [
          [BigInt.from(150000)],
          [BigInt.parse('9007199254740991')],
        ],
        moneyColumns: {0},
      );
      expect(table.excelRows(), [
        [150000],
        ['9007199254740991'],
      ]);
    },
  );
}
