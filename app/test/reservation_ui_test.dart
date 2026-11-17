import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/reservations/reservations_page.dart';
import 'package:ngoc_thanh_pos/features/reservations/reservation_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  testWidgets('Mở giao DH nạp đúng giỏ và giữ khách khi sang thanh toán', (
    tester,
  ) async {
    final s = (await tester.runAsync(salesFixture))!;
    addTearDown(s.db.close);
    await tester.runAsync(
      () => s.reserveItems(
        [const CartItem('v1', 2)],
        name: 'Khách giữ áo',
        duration: const Duration(hours: 24),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReservationsPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giao hàng · thanh toán'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Mobile tạo DH và hiển thị lượng giữ không xuất kho', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = (await tester.runAsync(salesFixture))!;
    addTearDown(s.db.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReservationsPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tạo phiếu giữ hàng'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Tên phụ huynh',
      ),
      'Phụ huynh mẫu',
    );
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giữ hàng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DH-CN01-A2-20261115-001'), findsOneWidget);
    expect(await tester.runAsync(() => s.availableQuantity('v1')), 9);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
