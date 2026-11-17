import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/transfers/transfers_page.dart';
import 'package:ngoc_thanh_pos/features/transfers/transfer_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/reservations/reservation_service.dart';

import 'transfer_fixtures.dart';

void main() {
  testWidgets('Mobile tạo phiếu xuất và giao vận chuyển', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = (await tester.runAsync(fixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransfersPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tạo phiếu xuất chuyển'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Lý do chuyển (bắt buộc)'), 'Điều hàng CN02');
    await tester.enterText(field('SL xuất'), '2');
    await tester.tap(find.text('Xác nhận xuất kho'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã xuất'), findsOneWidget);
    await tester.tap(find.text('Giao vận chuyển'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Lý do / ghi chú giao'), 'Giao xe nội bộ');
    await tester.tap(find.text('Xác nhận đang chuyển'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đang chuyển'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Máy nhận ghi số thực tế và thấy chênh lệch thiếu một áo', (
    tester,
  ) async {
    final s = (await tester.runAsync(fixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    final out = (await tester.runAsync(
      () => s.createTransferOut(
        targetDeviceId: 'd2',
        items: [const CartItem('v1', 5)],
        reason: 'Chuyển',
      ),
    ))!;
    await tester.runAsync(() => s.dispatchTransfer(out.id, 'Giao'));
    final t = (await tester.runAsync(() => targetFor(s, out.id)))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransfersPage(service: t)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hàng chờ nhận'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kiểm đếm · nhận hàng'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Thực nhận M'), '4');
    await tester.enterText(
      field('Lý do nhận / chênh lệch (bắt buộc)'),
      'Thiếu một áo',
    );
    await tester.tap(find.text('Xác nhận nhận hàng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('lệch -1'), findsOneWidget);
    expect(await tester.runAsync(() => t.availableQuantity('v1')), 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
