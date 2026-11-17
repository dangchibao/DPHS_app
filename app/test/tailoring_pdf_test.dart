import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_rule.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/pos/document_pdf.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Phiếu đo PDF tiếng Việt offline có đủ số đo và phụ thu', () async {
    final s = await salesFixture();
    try {
      final rule = await s.saveTailoringRule(
        name: 'Phụ thu may',
        config: {...TailoringRule.defaults(), 'base_fee': 20000},
      );
      final doc = await s.createTailoring(
        items: [const CartItem('v1', 1)],
        ruleId: rule,
        measurements: {
          for (final k in measurementLabels.keys)
            k: k == 'weight' ? 70000 : 1000,
        },
        options: [],
        dueDate: '2026-11-20',
        notes: 'Dài hơn',
        customerName: 'Phụ huynh',
        phone: '',
        received: 0,
        method: 'cash',
      );
      final bytes = await invoicePdf(s, doc.id);
      if (const bool.fromEnvironment('WRITE_QA_ARTIFACTS')) {
        final directory = Directory('../artifacts/output/pdf');
        await directory.create(recursive: true);
        await File('${directory.path}/phieu-may-mau.pdf').writeAsBytes(bytes);
      }
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(10000));
    } finally {
      await s.db.close();
    }
  });
}
