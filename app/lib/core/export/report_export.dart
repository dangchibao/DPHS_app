import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../local_service.dart';
import 'xlsx_export.dart';

String safeReportFilename(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .trim();
  return cleaned.length > 150 ? cleaned.substring(0, 150) : cleaned;
}

Future<bool> saveReportXlsx(
  LocalService service,
  String name,
  List<String> headers,
  List<List<Object?>> rows, {
  Set<int> moneyColumns = const {},
}) async {
  final bytes = buildXlsx(
    headers,
    rows,
    sheetName: 'Báo cáo',
    moneyColumns: moneyColumns,
  );
  final saved = await FilePicker.saveFile(
    fileName: '${safeReportFilename(name)}.xlsx',
    bytes: bytes,
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    dialogTitle: 'Lưu báo cáo Excel',
  );
  if (saved != null) {
    await service.db.transaction(
      () => service.audit(
        'DATA_EXPORT',
        'report',
        service.uuid.v7(),
        reason: 'Xuất Excel',
        changes: {'rows': rows.length, 'format': 'XLSX', 'name': name},
      ),
    );
  }
  return saved != null;
}

Future<Uint8List> buildReportPdf(
  String name,
  List<String> headers,
  List<List<Object?>> rows,
) async {
  final base = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      ),
      bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
      );
  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: base, bold: bold),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      maxPages: 500,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Text(
          'ĐỒNG PHỤC NGỌC THANH',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
        ),
        pw.SizedBox(height: 8),
        pw.Text(name),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: [
            for (final row in rows)
              [for (final value in row) value?.toString() ?? ''],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration:const pw.BoxDecoration(color:PdfColors.blue50),
          cellPadding: const pw.EdgeInsets.all(4),
        ),
      ],
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Trang ${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
    ),
  );
  return document.save();
}

Future<bool> saveReportPdf(
  LocalService service,
  String name,
  List<String> headers,
  List<List<Object?>> rows,
) async {
  final bytes = await buildReportPdf(name, headers, rows);
  final saved = await FilePicker.saveFile(
    fileName: '${safeReportFilename(name)}.pdf',
    bytes: bytes,
    mimeType: 'application/pdf',
    dialogTitle: 'Lưu báo cáo PDF',
  );
  if (saved != null) {
    await service.db.transaction(
      () => service.audit(
        'DATA_EXPORT',
        'report',
        service.uuid.v7(),
        reason: 'Xuất PDF',
        changes: {'rows': rows.length, 'format': 'PDF', 'name': name},
      ),
    );
  }
  return saved != null;
}
