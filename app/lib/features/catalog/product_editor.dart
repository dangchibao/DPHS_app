import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import 'catalog_service.dart';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../core/media/media_service.dart';
import '../../core/media/image_encoder.dart';

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
  Uint8List? photo;
  bool imageChanged = false;
  late Future<Uint8List?> initialPhoto;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    initialPhoto = widget.service.productImage(p?['image_path'] as String?);
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
        imageChanged: imageChanged,
        image: photo,
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
            const Text(
              'Ảnh chung cho mọi size/màu của sản phẩm. JPEG/PNG tối đa 8MB; ảnh sẽ được nén và lưu trong bản sao lưu máy.',
            ),
            SizedBox(
              height: 150,
              child: imageChanged
                  ? (photo == null
                        ? const Icon(Icons.checkroom, size: 64)
                        : Image.memory(photo!, fit: BoxFit.contain))
                  : FutureBuilder<Uint8List?>(
                      future: initialPhoto,
                      builder: (_, snapshot) => snapshot.data == null
                          ? const Icon(Icons.checkroom, size: 64)
                          : Image.memory(
                              snapshot.data!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.checkroom, size: 64),
                            ),
                    ),
            ),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : pickPhoto,
                  child: const Text('Chọn ảnh sản phẩm'),
                ),
                if (widget.product?['image_path'] != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final bytes = await initialPhoto;
                            if (!mounted) return;
                            setState(() {
                              if (bytes == null) {
                                error = 'Ảnh không còn trong cache. Hãy chọn lại ảnh nguồn.';
                              } else {
                                photo = bytes;
                                imageChanged = true;
                                error = null;
                              }
                            });
                          },
                    child: const Text('Gửi lại ảnh hiện tại'),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          imageChanged = true;
                          photo = null;
                        }),
                  child: const Text('Bỏ ảnh'),
                ),
              ],
            ),
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
  Future<void> pickPhoto() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
      if (file == null) return;
      if ((file.lengthSync() ?? 0) > 8 * 1024 * 1024) {
        throw ArgumentError('Ảnh tối đa 8MB.');
      }
      final data = BytesBuilder(copy: false);
      await for (final part in file.readAsByteStream()) {
        if (data.length + part.length > 8 * 1024 * 1024) {
          throw ArgumentError('Ảnh tối đa 8MB.');
        }
        data.add(part);
      }
      final compressed = await prepareImage(data.takeBytes());
      if (mounted) {
        setState(() {
          photo = compressed;
          imageChanged = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
