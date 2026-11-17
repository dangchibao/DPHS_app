import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/pos/pos_page.dart';
import 'package:ngoc_thanh_pos/features/pricing/commercial_rule.dart';
import 'package:ngoc_thanh_pos/features/pricing/commercial_service.dart';

import 'fixtures.dart';

void main() {
  testWidgets('POS mobile áp voucher tính lại tổng, nhập sai chặn hoàn tất', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = await salesFixture();
    addTearDown(service.db.close);
    await service.saveCommercialRule(
      name: 'Đầu năm 10%',
      kind: 'promotion',
      config: {
        ...CommercialRule.defaults(),
        'value': 1000,
        'discount_type': 'percent',
        'voucher': 'DAUNAM',
      },
    );
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
    await tester.tap(find.text('Thanh toán · F9'));
    await tester.pumpAndSettle();
    final dropdown = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Khuyến mãi / voucher',
    );
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đầu năm 10%').last);
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Hoàn tất thanh toán');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    final voucher = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Mã voucher',
    );
    await tester.ensureVisible(voucher);
    await tester.enterText(voucher, 'DAUNAM');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(find.textContaining('Giảm khuyến mãi:'), findsOneWidget);
    expect(find.textContaining('90.000'), findsWidgets);
    await tester.enterText(voucher, 'SAI');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Quay lại'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
