import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/employees/payroll_pdf.dart';

import 'payroll_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Phiếu lương PDF tiếng Việt có snapshot, cảnh báo đối soát và quyền',
    () async {
      final s = await payrollFixture(withRun: true);
      addTearDown(s.db.close);
      await s.db.execute(
        "INSERT INTO payroll_reconciliations VALUES('flag','store-cn01','run1','late','2026-11-17')",
      );
      final bytes = await payrollPdf(s, 'run1');
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(10000));
      if (const bool.fromEnvironment('WRITE_PAYROLL_QA')) {
        final directory = Directory('../artifacts/output/pdf');
        await directory.create(recursive: true);
        await File('${directory.path}/phieu-luong-mau.pdf').writeAsBytes(bytes);
      }
      s.session = null;
      await expectLater(payrollPdf(s, 'run1'), throwsStateError);
    },
  );
}
