import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/pos/pos_page.dart';

import 'fixtures.dart';

void main() {
  testWidgets('POS mobile mở giỏ và thao tác số lượng không tràn bố cục', (
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
        home: Scaffold(body: PosPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Áo sơ mi').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Giỏ hàng (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
