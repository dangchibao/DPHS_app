import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import 'catalog_service.dart';

class ProductEditor extends StatefulWidget {
  const ProductEditor({
    super.key,
    required this.service,
    this.product,
    this.asNewVariant = false,
  });
  final LocalService service;
  final Map<String, Object?>? product;
  final bool asNewVariant;
  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  late final Map<String, TextEditingController> fields;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    fields = {
      for (final e in {
        'Tên sản phẩm': p?['name'] ?? '',
        'Nhóm hàng': p?['category'] ?? 'Áo sơ mi',
        'Giới tính': p?['gender'] ?? 'Unisex',
        'Cấp học': p?['school_level'] ?? 'Tiểu học',
        'Năm học': p?['school_year'] ?? '2026–2027',
        'Size': widget.asNewVariant ? '' : p?['size'] ?? '',
        'Màu': p?['color'] ?? 'Trắng',
        'Đơn vị': p?['unit'] ?? 'cái',
        'Mã sản phẩm': widget.asNewVariant ? '' : p?['sku'] ?? '',
        'Mã vạch': widget.asNewVariant ? '' : p?['barcode'] ?? '',
        'Giá bán': p?['price'] ?? 0,
        'Giá vốn': p?['cost'] ?? 0,
        'Ngưỡng sắp hết': p?['threshold'] ?? 5,
      }.entries)
        e.key: TextEditingController(text: '${e.value}'),
    };
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    String text(String key) => fields[key]!.text;
    try {
      await widget.service.saveVariant(
        existing: widget.asNewVariant ? null : widget.product,
        parentId: widget.asNewVariant
            ? widget.product!['product_id'] as String
            : null,
        name: text('Tên sản phẩm'),
        category: text('Nhóm hàng'),
        gender: text('Giới tính'),
        level: text('Cấp học'),
        year: text('Năm học'),
        size: text('Size'),
        color: text('Màu'),
        unit: text('Đơn vị'),
        sku: text('Mã sản phẩm'),
        barcode: text('Mã vạch'),
        price: int.parse(text('Giá bán')),
        cost: int.parse(text('Giá vốn')),
        threshold: int.parse(text('Ngưỡng sắp hết')),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? 'Giá và ngưỡng phải là số nguyên.'
              : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.asNewVariant
          ? 'Thêm size / màu'
          : widget.product == null
          ? 'Thêm sản phẩm'
          : 'Chỉnh sửa sản phẩm',
    ),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  controller: entry.value,
                  enabled: !busy,
                  keyboardType:
                      [
                        'Giá bán',
                        'Giá vốn',
                        'Ngưỡng sắp hết',
                      ].contains(entry.key)
                      ? TextInputType.number
                      : TextInputType.text,
                  decoration: InputDecoration(labelText: entry.key),
                ),
              ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, false),
        child: const Text('Đóng'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Đang lưu…' : 'Lưu sản phẩm'),
      ),
    ],
  );
}
