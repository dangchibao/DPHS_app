import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/returns/returns_page.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  testWidgets('Mobile nhận trả, hoàn tiền và hiện phiếu DT trong lịch sử', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await salesFixture();
    addTearDown(s.db.close);
    await s.sell(
      items: [const CartItem('v1', 1)],
      discount: 0,
      received: 100000,
      method: 'cash',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReturnsPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đổi size / đổi trả'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Số lượng nhận lại'), '1');
    await tester.pumpAndSettle();
    expect(find.textContaining('Hoàn lại: 100.000'), findsOneWidget);
    final reason = field('Lý do đổi/trả (bắt buộc)');
    await tester.ensureVisible(reason);
    await tester.enterText(reason, 'Không vừa');
    await tester.tap(find.text('Xác nhận đổi/trả'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Phiếu đổi/trả'));
    await tester.pumpAndSettle();
    expect(find.text('DT-CN01-A2-20261115-001'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
