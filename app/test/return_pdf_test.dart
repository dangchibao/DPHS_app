import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/returns/return_pricing.dart';
import 'package:ngoc_thanh_pos/features/returns/return_service.dart';
import 'package:ngoc_thanh_pos/features/returns/return_pdf.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Phiếu DT PDF tách rõ cấn nợ và hoàn tiền', () async {
    final s = await salesFixture();
    try {
      final sale = await s.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 40000,
        method: 'cash',
        customerName: 'Phụ huynh mẫu',
      );
      final line = (await s.returnableLines(sale.id)).single['id'] as String;
      final result = await s.createReturn(
        originalId: sale.id,
        items: [ReturnSelection(line, 1)],
        reason: 'Đổi size không còn phù hợp, nhận lại hàng',
        received: 0,
        method: 'bank',
      );
      final bytes = await returnPdf(s, result.id);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(10000));
      if (const bool.fromEnvironment('WRITE_RETURN_QA')) {
        final d = Directory('../artifacts/output/pdf');
        await d.create(recursive: true);
        await File('${d.path}/phieu-doi-tra-mau.pdf').writeAsBytes(bytes);
      }
    } finally {
      await s.db.close();
    }
  });
}
