import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/export/report_export.dart';
import 'package:ngoc_thanh_pos/core/export/xlsx_export.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/reports/report_service.dart';
import 'package:ngoc_thanh_pos/core/money.dart';

import 'payroll_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Xuất bảng thật: Excel/PDF tiếng Việt, tên file hợp lệ, số tiền nguyên',
    () async {
      final s = await payrollFixture();
      addTearDown(s.db.close);
      await s.sell(
        items: [const CartItem('v1', 2)],
        discount: 10000,
        received: 190000,
        method: 'cash',
      );
      final data = await s.localReport(ReportRange('2026-11-01', '2026-11-15'));
      final table = data.tables['Sản phẩm · lãi gộp']!;
      final xlsx = buildXlsx(
        table.headers,
        table.excelRows(),
        moneyColumns: table.moneyColumns,
      );
      expect(xlsx.take(2), [80, 75]);
      final pdf = await buildReportPdf(
        'NT-CN01 · Sản phẩm/lãi gộp · 2026-11-01 đến 2026-11-15',
        table.headers,
        [
          for (final row in table.rows)
            [
              for (var i = 0; i < row.length; i++)
                if (row[i] is BigInt)
                  table.moneyColumns.contains(i)
                      ? formatWholeVnd(row[i] as BigInt)
                      : (row[i] as BigInt).toString()
                else
                  row[i],
            ],
        ],
      );
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      expect(safeReportFilename('Trường A/B: báo cáo'), 'Trường A_B_ báo cáo');
      if (const bool.fromEnvironment('WRITE_REPORT_QA')) {
        final directory = Directory('../artifacts/output/pdf');
        await directory.create(recursive: true);
        await File('${directory.path}/bao-cao-lai-gop-mau.pdf')
            .writeAsBytes(pdf);
        await File('../artifacts/bao-cao-lai-gop-mau.xlsx').writeAsBytes(xlsx);
      }
    },
  );
}
