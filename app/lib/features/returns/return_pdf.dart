import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../pos/document_pdf.dart';

Future<Uint8List> returnPdf(LocalService service, String id) async {
  service.require(Permission.returns);
  final doc = (await service.db.rows(
        "SELECT * FROM documents WHERE store_id=? AND id=? AND type='DT'",
        [service.storeId, id],
      )).single,
      m = jsonDecode(doc['metadata_json'] as String) as Map,
      returned = await service.db.rows(
        'SELECT r.quantity,r.credit,l.name,l.size,l.color,l.unit FROM return_lines r JOIN invoice_lines l ON l.id=r.original_line_id AND l.store_id=r.store_id WHERE r.store_id=? AND r.document_id=? ORDER BY r.id',
        [service.storeId, id],
      ),
      replacements = await service.db.rows(
        'SELECT * FROM invoice_lines WHERE store_id=? AND document_id=? ORDER BY id',
        [service.storeId, id],
      );
  final money = NumberFormat.currency(
        locale: 'vi_VN',
        symbol: 'đ',
        decimalDigits: 0,
      ),
      pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: pw.Font.ttf(
            await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
          ),
          bold: pw.Font.ttf(
            await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
          ),
        ),
      );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(22),
      build: (_) => [
        pw.Center(
          child: pw.Text(
            'ĐỒNG PHỤC NGỌC THANH',
            style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            m['void_original'] == true
                ? 'PHIẾU HỦY HÓA ĐƠN'
                : 'PHIẾU ĐỔI / TRẢ HÀNG',
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Mã phiếu: ${doc['code']}'),
        pw.Text('Chứng từ gốc: ${m['original_code']}'),
        pw.Text(
          'Ngày: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(doc['issued_at'] as String).toUtc().add(const Duration(hours: 7)))}',
        ),
        if ((m['customer_name'] ?? '').toString().isNotEmpty)
          pw.Text('Khách: ${m['customer_name']}'),
        pw.Text('Lý do: ${m['reason']}'),
        pw.SizedBox(height: 12),
        pw.Text(
          'HÀNG NHẬN LẠI',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.TableHelper.fromTextArray(
          headers: ['Sản phẩm / size / màu', 'SL', 'Giá trị nhận lại'],
          data: [
            for (final r in returned)
              [
                '${r['name']}\n${r['size']} · ${r['color']}',
                r['quantity'],
                money.format(r['credit']),
              ],
          ],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellPadding: const pw.EdgeInsets.all(5),
        ),
        if (replacements.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'HÀNG THAY THẾ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.TableHelper.fromTextArray(
            headers: ['Sản phẩm / size / màu', 'SL', 'Giá trị'],
            data: [
              for (final r in replacements)
                [
                  '${r['name']}\n${r['size']} · ${r['color']}',
                  r['quantity'],
                  money.format(
                    (r['unit_price'] as int) * (r['quantity'] as int) -
                        (r['discount'] as int),
                  ),
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellPadding: const pw.EdgeInsets.all(5),
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Container(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Giá trị nhận lại: ${money.format(m['returned_value'])}'),
              pw.Text('Hàng thay thế: ${money.format(m['replacement_value'])}'),
              pw.Text('Cấn nợ chứng từ gốc: ${money.format(m['debt_offset'])}'),
              if ((m['refund'] as int) > 0)
                pw.Text(
                  'HOÀN LẠI: ${money.format(m['refund'])}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                )
              else ...[
                pw.Text(
                  'Chênh lệch cần thu: ${money.format(m['cash_due'])}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text('Đã nhận thêm: ${money.format(m['received'])}'),
                pw.Text('Công nợ mới: ${money.format(m['new_debt'])}'),
              ],
              pw.SizedBox(height: 10),
              pw.Text(
                'Chứng từ gốc được giữ nguyên. Phiếu này ghi nhận đổi/trả và thu/hoàn riêng.',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
      ],
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
    ),
  );
  return pdf.save();
}

Future<void> showReturnPdf(
  BuildContext context,
  LocalService service,
  String id,
) async {
  final bytes = await returnPdf(service, id);
  if (context.mounted) {
    await showDocumentPdf(context, service, id, bytes);
  }
}
