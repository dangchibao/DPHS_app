import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/pos/pos_page.dart';
import 'package:ngoc_thanh_pos/features/pos/pricing.dart';
import 'package:ngoc_thanh_pos/features/catalog/combo_service.dart';

import 'fixtures.dart';

void main() {
  testWidgets(
    'POS mobile chọn hai size riêng cho combo và bỏ combo trả giỏ về trống',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = await salesFixture();
      addTearDown(service.db.close);
      await service.db.execute(
        "INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES('v2','p1','SKU-L','L','Xanh','cái',45000,100000,'2026-11-15')",
      );
      await service.adjustStock('v2', 5, 'Nhập size L');
      await service.saveCombo(
        name: 'Hai áo hai size',
        price: 150001,
        parts: [const ComboPart('p1', 1), const ComboPart('p1', 1)],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PosPage(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Giỏ hàng (0)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chọn combo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hai áo hai size'));
      await tester.pumpAndSettle();
      final fields = find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<String>,
      );
      await tester.tap(fields.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Size M · Trắng · Còn 10').last);
      await tester.pumpAndSettle();
      await tester.tap(fields.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Size L · Xanh · Còn 5').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm đủ món vào giỏ'));
      await tester.pumpAndSettle();
      final cartSheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: cartSheet, matching: find.text('M · Trắng')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cartSheet, matching: find.text('L · Xanh')),
        findsOneWidget,
      );
      expect(find.textContaining('150.001'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Bỏ combo'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cartSheet, matching: find.text('M · Trắng')),
        findsNothing,
      );
      expect(
        find.descendant(of: cartSheet, matching: find.text('L · Xanh')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
