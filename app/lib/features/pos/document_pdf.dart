import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../tailoring/tailoring_rule.dart';

abstract interface class DirectPrinterAdapter {
  Future<void> printBytes(Uint8List bytes);
}

class DeferredPrinterAdapter implements DirectPrinterAdapter {
  @override
  Future<void> printBytes(Uint8List bytes) => Future.error(
    UnsupportedError('Kết nối máy in trực tiếp được triển khai sau.'),
  );
}

final _money = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: 'đ',
  decimalDigits: 0,
);

Future<Uint8List> invoicePdf(LocalService service, String id) async {
  service.require(
    service.session?.can(Permission.sell) == true
        ? Permission.sell
        : Permission.tailoring,
  );
  final invoice = (await service.db.rows(
    'SELECT * FROM documents WHERE store_id=? AND id=?',
    [service.storeId, id],
  )).single;
  service.require(
    invoice['type'] == 'MR' ? Permission.tailoring : Permission.sell,
  );
  final lines = await service.db.rows(
    'SELECT * FROM invoice_lines WHERE store_id=? AND document_id=? ORDER BY id',
    [service.storeId, id],
  );
  final metadata = jsonDecode(invoice['metadata_json'] as String) as Map;
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: invoice['type'] == 'MR' ? PdfPageFormat.a4 : PdfPageFormat.a5,
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
            invoice['type'] == 'MR'
                ? 'PHIẾU ĐẶT MAY / ĐO SIZE'
                : 'HÓA ĐƠN BÁN HÀNG',
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Mã: ${invoice['code']}'),
        pw.Text(
          'Ngày: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(invoice['issued_at'] as String).toUtc().add(const Duration(hours: 7)))}',
        ),
        if (metadata['school_name'] != null)
          pw.Text('Trường: ${metadata['school_name']}'),
        if (metadata['student_name'] != null)
          pw.Text(
            'Học sinh: ${metadata['student_name']} · Lớp ${metadata['class_name']} · ${invoice['school_year']}',
          ),
        if ((metadata['customer_name'] ?? '').toString().isNotEmpty)
          pw.Text(
            'Khách: ${metadata['customer_name']}${(metadata['phone'] ?? '').toString().isEmpty ? '' : ' · ${metadata['phone']}'}',
          ),
        pw.SizedBox(height: 14),
        if (invoice['type'] == 'MR') ...[
          pw.Text(
            'Hẹn trả: ${DateFormat('dd/MM/yyyy').format(DateTime.parse((metadata['tailoring'] as Map)['due_date'] as String))}',
          ),
          pw.Text(
            'Bảng phụ thu: ${(metadata['tailoring'] as Map)['rule_name']}',
          ),
          pw.Text(
            'Phụ thu mỗi món: ${_money.format((metadata['tailoring'] as Map)['per_unit_fee'])}',
          ),
          pw.TableHelper.fromTextArray(
            headers: ['Số đo', 'Giá trị'],
            data: [
              for (final e in measurementLabels.entries)
                [
                  e.value,
                  '${measurementText(((metadata['tailoring'] as Map)['measurements'] as Map)[e.key] as int, e.key)} ${e.key == 'weight' ? 'kg' : 'cm'}',
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          if (((metadata['tailoring'] as Map)['option_labels'] as List)
              .isNotEmpty)
            pw.Text(
              'Yêu cầu: ${((metadata['tailoring'] as Map)['option_labels'] as List).join(', ')}',
            ),
          pw.Text('Ghi chú: ${(metadata['tailoring'] as Map)['notes']}'),
          pw.SizedBox(height: 12),
        ],
        for (final combo in (metadata['combo_snapshots'] as List? ?? []))
          pw.Text(
            'Combo: ${combo['name']} ×${combo['quantity']} · ${_money.format((combo['price'] as int) * (combo['quantity'] as int))}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        pw.TableHelper.fromTextArray(
          headers: [
            'Sản phẩm / size / màu',
            'SL',
            'Đơn giá',
            'Giảm/dòng',
            'Thành tiền',
          ],
          data: [
            for (final line in lines)
              [
                '${line['name']}\n${line['size']} · ${line['color']} · ${line['unit']}',
                line['quantity'],
                _money.format(line['unit_price']),
                _money.format(line['discount']),
                _money.format(
                  (line['quantity'] as int) * (line['unit_price'] as int) -
                      (line['discount'] as int),
                ),
              ],
          ],
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.all(5),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Tiền hàng: ${_money.format(invoice['subtotal'])}'),
              pw.Text('Giảm giá: ${_money.format(invoice['discount'])}'),
              if (metadata['price_list_name'] != null)
                pw.Text('Bảng giá: ${metadata['price_list_name']}'),
              if (metadata['promotion_name'] != null)
                pw.Text(
                  'Ưu đãi: ${metadata['promotion_name']} · ${_money.format(metadata['promotion_discount'])}',
                ),
              pw.Text(
                'TỔNG CỘNG: ${_money.format(invoice['total'])}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              pw.Text(
                '${invoice['type'] == 'MR' ? 'Thanh toán khi nhận' : 'Thanh toán khi bán'}: ${_money.format(metadata['paid'] ?? 0)}',
              ),
              pw.Text(
                '${invoice['type'] == 'MR' ? 'Còn nợ khi nhận' : 'Còn nợ khi bán'}: ${_money.format((invoice['total'] as int) - (metadata['paid'] as int? ?? 0))}',
              ),
              pw.SizedBox(height: 18),
              pw.Center(child: pw.Text('Cảm ơn quý phụ huynh!')),
            ],
          ),
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
  return doc.save();
}

Future<void> showInvoicePdf(
  BuildContext context,
  LocalService service,
  String id,
) async {
  final bytes = await invoicePdf(service, id);
  if (context.mounted) {
    await showDocumentPdf(context, service, id, bytes);
  }
}

Future<void> showDocumentPdf(
  BuildContext context,
  LocalService service,
  String id,
  Uint8List bytes,
) async {
  final invoice = (await service.db.rows(
    'SELECT code FROM documents WHERE store_id=? AND id=?',
    [service.storeId, id],
  )).single;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 800,
        height: 700,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text('Xem trước · ${invoice['code']}')),
                  TextButton.icon(
                    onPressed: () async {
                      await service.db.transaction(
                        () => service.audit(
                          'DATA_EXPORT',
                          'document',
                          id,
                          reason: 'Xuất chứng từ PDF',
                          changes: {'format': 'PDF'},
                        ),
                      );
                      await Printing.sharePdf(
                        bytes: bytes,
                        filename: '${invoice['code']}.pdf',
                      );
                    },
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Lưu PDF'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PdfPreview(
                build: (_) => bytes,
                allowPrinting: false,
                allowSharing: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
