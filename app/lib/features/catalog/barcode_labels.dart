import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';

Future<Uint8List> barcodeLabelsPdf(
  Map<String, Object?> variant, {
  required double widthMm,
  required double heightMm,
  required int copies,
}) async {
  final barcode = (variant['barcode'] as String? ?? '').trim();
  if (!widthMm.isFinite ||
      !heightMm.isFinite ||
      widthMm < 30 ||
      widthMm > 150 ||
      heightMm < 20 ||
      heightMm > 100 ||
      copies < 1 ||
      copies > 500 ||
      barcode.isEmpty ||
      barcode.length > 80 ||
      !RegExp(r'^[\x20-\x7E]+$').hasMatch(barcode)) {
    throw ArgumentError(
      'Tem cần mã vạch ASCII 1–80 ký tự, khổ 30–150 × 20–100 mm, 1–500 bản.',
    );
  }
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  final format = PdfPageFormat(
    widthMm * PdfPageFormat.mm,
    heightMm * PdfPageFormat.mm,
    marginAll: 2 * PdfPageFormat.mm,
  );
  final money = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );
  for (var i = 0; i < copies; i++) {
    document.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.FittedBox(
              child: pw.Text(
                '${variant['name']}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
              ),
            ),
            pw.FittedBox(
              child: pw.Text(
                'Size ${variant['size']} · ${variant['color']} · ${money.format(variant['sale_price'] ?? variant['price'])}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Expanded(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: barcode,
                drawText: false,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(barcode, style: const pw.TextStyle(fontSize: 7)),
            ),
          ],
        ),
      ),
    );
  }
  return document.save();
}

class BarcodeLabelsPage extends StatefulWidget {
  const BarcodeLabelsPage({super.key, required this.service});
  final LocalService service;
  @override
  State<BarcodeLabelsPage> createState() => _BarcodeLabelsPageState();
}

class _BarcodeLabelsPageState extends State<BarcodeLabelsPage> {
  final width = TextEditingController(text: '50'),
      height = TextEditingController(text: '30'),
      copies = TextEditingController(text: '1');
  late Future<List<Map<String, Object?>>> variants;
  Map<String, Object?>? selected;
  Uint8List? bytes;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    variants = widget.service.catalog();
  }

  @override
  void dispose() {
    width.dispose();
    height.dispose();
    copies.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (selected == null) throw ArgumentError('Chọn biến thể cần in tem.');
      final w = double.tryParse(width.text),
          h = double.tryParse(height.text),
          n = int.tryParse(copies.text);
      if (w == null || h == null || n == null || !w.isFinite || !h.isFinite) {
        throw ArgumentError('Nhập khổ tem và số bản hợp lệ.');
      }
      await widget.service.catalog();
      final result = await barcodeLabelsPdf(
        selected!,
        widthMm: w,
        heightMm: h,
        copies: n,
      );
      if (mounted) setState(() => bytes = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        FutureBuilder(
          future: variants,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('${snapshot.error}');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Biến thể / mã vạch',
              ),
              items: [
                for (final p in snapshot.data!)
                  DropdownMenuItem(
                    value: p['id'] as String,
                    child: Text(
                      '${p['name']} · ${p['size']} · ${p['color']} · ${p['barcode'] ?? 'Chưa có mã vạch'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (id) => setState(() {
                      selected = snapshot.data!.firstWhere(
                        (p) => p['id'] == id,
                      );
                      bytes = null;
                    }),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final e in [
              (width, 'Rộng (mm)'),
              (height, 'Cao (mm)'),
              (copies, 'Số bản'),
            ])
              SizedBox(
                width: 120,
                child: TextField(
                  controller: e.$1,
                  enabled: !busy,
                  onChanged: (_) => setState(() => bytes = null),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: e.$2),
                ),
              ),
            FilledButton.icon(
              onPressed: busy ? null : generate,
              icon: const Icon(Icons.preview_outlined),
              label: Text(busy ? 'Đang tạo…' : 'Xem trước'),
            ),
            if (bytes != null)
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          await widget.service.catalog();
                          await widget.service.db.transaction(
                            () => widget.service.audit(
                              'DATA_EXPORT',
                              'variant',
                              selected!['id'] as String,
                              reason: 'Xuất tem mã vạch PDF',
                              changes: {
                                'width_mm': width.text,
                                'height_mm': height.text,
                                'copies': copies.text,
                              },
                            ),
                          );
                          await Printing.sharePdf(
                            bytes: bytes!,
                            filename: 'tem-ma-vach.pdf',
                          );
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        }
                      },
                icon: const Icon(Icons.save_alt),
                label: const Text('Lưu PDF'),
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: bytes == null
              ? const Center(child: Text('Chọn khổ tem phù hợp rồi tạo PDF.'))
              : PdfPreview(
                  build: (_) => bytes!,
                  allowPrinting: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                ),
        ),
      ],
    ),
  );
}
