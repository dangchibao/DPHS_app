import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_page.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_rule.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_service.dart';

import 'fixtures.dart';

void main() {
  testWidgets('Mobile nhận phiếu may đủ số đo và chuyển sang đang may', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await salesFixture();
    addTearDown(s.db.close);
    await s.saveTailoringRule(
      name: 'May mẫu',
      config: {...TailoringRule.defaults(), 'base_fee': 20000},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TailoringPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhận đơn may'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Tên khách / học sinh'), 'Phụ huynh thử may');
    for (final e in measurementLabels.entries) {
      final input = field('${e.value} (${e.key == 'weight' ? 'kg' : 'cm'})');
      await tester.ensureVisible(input);
      await tester.enterText(input, e.key == 'weight' ? '70' : '100');
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Nhận đơn'));
    await tester.pumpAndSettle();
    expect(find.textContaining('MR-CN01-A2-20261115-001'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final next = find.text('→ Đang may');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.enterText(
      field('Ghi chú cập nhật (bắt buộc)'),
      'Giao thợ may',
    );
    await tester.tap(find.text('Cập nhật'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('MR-CN01-A2-20261115-001 · Đang may'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
