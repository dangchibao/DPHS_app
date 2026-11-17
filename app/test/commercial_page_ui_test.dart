import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/pricing/commercial_page.dart';

import 'fixtures.dart';

void main() {
  testWidgets('Mobile tạo khuyến mãi và đóng hộp sửa khi ô nhập đang focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = await salesFixture();
    addTearDown(service.db.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CommercialPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bảng giá / khuyến mãi'));
    await tester.pumpAndSettle();
    final name = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Tên chương trình / bảng giá',
    );
    final value = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Mức giảm (VND)',
    );
    await tester.enterText(name, 'Ưu đãi thử');
    await tester.ensureVisible(value);
    await tester.enterText(value, '10000');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Ưu đãi thử'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ưu đãi thử'));
    await tester.pumpAndSettle();
    await tester.enterText(name, 'Chưa lưu');
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Ưu đãi thử'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
