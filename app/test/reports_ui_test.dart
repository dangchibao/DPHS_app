import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/reports/reports_page.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'payroll_fixtures.dart';

void main() {
  testWidgets(
    'Dashboard mobile đọc số tiền thật từ giao dịch offline và có xuất báo cáo',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = (await tester.runAsync(() => payrollFixture()))!;
      addTearDown(() => tester.runAsync(s.db.close));
      await tester.runAsync(
        () => s.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 100000,
          method: 'cash',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportsPage(service: s)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dashboard · báo cáo'), findsOneWidget);
      expect(find.text('Doanh thu thuần'), findsWidgets);
      expect(find.text('100.000 đ'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Xuất Excel'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Xuất PDF'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
