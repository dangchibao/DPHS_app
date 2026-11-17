import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/employees/attendance_page.dart';
import 'package:ngoc_thanh_pos/features/employees/attendance_service.dart';

import 'attendance_fixtures.dart';

void main() {
  testWidgets('Mobile ghi nửa ngày và hiện chờ xác nhận đồng bộ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = (await tester.runAsync(attendanceFixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AttendancePage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi ngày công'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đủ ngày (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nửa ngày (0,5)').last);
    await tester.pumpAndSettle();
    final reason = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Lý do / ghi chú (bắt buộc)',
    );
    await tester.enterText(reason, 'Làm buổi sáng');
    await tester.tap(find.text('Lưu ngày công'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0,5 ngày · Chờ đồng bộ'), findsOneWidget);
    final rows = (await tester.runAsync(
      () => s.attendance(from: '2026-11-01', to: '2026-12-01'),
    ))!;
    expect(rows.single['day_units'], 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
