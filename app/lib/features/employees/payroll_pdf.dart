import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import 'attendance_service.dart';

Future<Uint8List> payrollPdf(LocalService service, String id) async {
  final actor = service.require(Permission.payroll);
  final row = (await service.db.rows(
    'SELECT p.*,v.reason AS void_reason,EXISTS(SELECT 1 FROM payroll_reconciliations r WHERE r.store_id=p.store_id AND r.run_id=p.id) AS needs_reconcile FROM payroll_runs p LEFT JOIN payroll_voids v ON v.store_id=p.store_id AND v.run_id=p.id WHERE p.store_id=? AND p.id=?',
    [service.storeId, id],
  )).single;
  final store = (await service.db.rows(
    'SELECT name,code FROM stores WHERE id=?',
    [service.storeId],
  )).single;
  final totals = jsonDecode(row['totals_json'] as String) as Map,
      config = jsonDecode(row['config_json'] as String) as Map;
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      ),
      bold: pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
      ),
    ),
  );
  final money = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Text(
          'ĐỒNG PHỤC NGỌC THANH',
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text('${store['name']} - ${store['code']}'),
        pw.SizedBox(height: 12),
        pw.Text(
          'PHIẾU LƯƠNG',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text('Kỳ ${(row['period_start'] as String).substring(0, 7)}'),
        pw.SizedBox(height: 10),
        pw.Text('Nhân viên: ${row['employee_name']}'),
        pw.Text(
          'Mã phiếu: ${row['id']}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.Text('Phát hành: ${row['created_at']}'),
        pw.SizedBox(height: 10),
        if (row['void_reason'] != null)
          pw.Text(
            'ĐÃ HỦY: ${row['void_reason']}',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
        if (row['needs_reconcile'] == 1 && row['void_reason'] == null)
          pw.Text(
            'CẦN ĐỐI SOÁT: có giao dịch bổ sung sau khi chốt. Không tự sửa số tiền trên phiếu.',
            style: pw.TextStyle(
              color: PdfColors.red,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        pw.TableHelper.fromTextArray(
          headers: ['Khoản mục', 'Giá trị'],
          data: [
            ['Lương cơ bản', money.format(config['base_salary'])],
            [
              'Công ghi nhận',
              '${daysText(totals['attendance_units'] as int)} ngày',
            ],
            [
              'Công tính lương',
              '${daysText(totals['paid_units'] as int)} / ${config['standard_days']} ngày',
            ],
            ['Doanh số thuần', money.format(totals['net_sales'])],
            ['Lương theo công', money.format(totals['base_pay'])],
            ['Hoa hồng', money.format(totals['commission_pay'])],
            ['Thưởng doanh số', money.format(totals['bonus_pay'])],
            ['TỔNG LƯƠNG', money.format(totals['total_pay'])],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.all(5),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Lương theo công và hoa hồng làm tròn xuống VND. Thưởng chỉ lấy bậc cao nhất. Phiếu ghi nhận số lương phát hành, không xác nhận chuyển tiền ngân hàng.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('Người lập'), pw.Text('Nhân viên')],
        ),
      ],
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
    ),
  );
  if (service.require(Permission.payroll).userId != actor.userId) {
    throw StateError('Phiên đã thay đổi.');
  }
  return pdf.save();
}
