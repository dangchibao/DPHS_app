import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/employees/payroll_page.dart';

import 'payroll_fixtures.dart';

void main() {
  test('Hoa hồng phần trăm không dùng float', () {
    expect(commissionBasisPoints('1,25'), 125);
    expect(commissionBasisPoints('0.01'), 1);
    expect(commissionBasisPoints('100'), 10000);
    for (final value in ['100,01', '1,234', '-1', 'NaN']) {
      expect(() => commissionBasisPoints(value), throwsArgumentError);
    }
  });
  testWidgets(
    'Mobile xem phiếu thật, cấu hình lương offline và không overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = (await tester.runAsync(() => payrollFixture(withRun: true)))!;
      addTearDown(() => tester.runAsync(s.db.close));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PayrollPage(service: s)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lương cơ bản · hoa hồng · thưởng'), findsOneWidget);
      await tester.tap(find.text('Cấu hình lương'));
      await tester.pumpAndSettle();
      expect(find.text('Cấu hình lương theo kỳ'), findsOneWidget);
      await tester.tap(find.text('Lưu yêu cầu cấu hình'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => s.db.rows('SELECT id FROM payroll_commands'),
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
