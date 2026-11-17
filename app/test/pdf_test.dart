import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/pos/document_pdf.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/catalog/barcode_labels.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Tem PDF theo khổ cấu hình; từ chối số bản và mã không hợp lệ',
    () async {
      final variant = <String, Object?>{
        'name': 'Áo sơ mi trắng',
        'size': 'M',
        'color': 'Trắng',
        'sale_price': 100000,
        'barcode': 'NT-ASM-M-01',
      };
      final bytes = await barcodeLabelsPdf(
        variant,
        widthMm: 50,
        heightMm: 30,
        copies: 2,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      await expectLater(
        barcodeLabelsPdf(variant, widthMm: 50, heightMm: 30, copies: 501),
        throwsArgumentError,
      );
      await expectLater(
        barcodeLabelsPdf(
          {...variant, 'barcode': 'Áo'},
          widthMm: 50,
          heightMm: 30,
          copies: 1,
        ),
        throwsArgumentError,
      );
    },
  );
  test('PDF hóa đơn offline dùng font tiếng Việt đã đóng gói', () async {
    final service = await salesFixture();
    try {
      final sale = await service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 100000,
        method: 'cash',
      );
      final bytes = await invoicePdf(service, sale.id);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(10000));
    } finally {
      await service.db.close();
    }
  });
}
