import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/sync/cloud_api.dart';
import '../../core/money.dart';

class WebCatalogPage extends StatefulWidget {
  const WebCatalogPage({
    super.key,
    required this.api,
    required this.storeId,
    required this.deviceId,
    required this.userId,
  });
  final CloudApi api;
  final String storeId, deviceId, userId;
  @override
  State<WebCatalogPage> createState() => _WebCatalogPageState();
}

class _WebCatalogPageState extends State<WebCatalogPage> {
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  String cursor = '', error = '';
  bool busy = false, more = false, inactive = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool next = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final query = Uri(
        queryParameters: {
          'search': search.text.trim(),
          'inactive': inactive ? '1' : '0',
          if (next) 'cursor': cursor,
        },
      ).query;
      final result = await widget.api.send('/web/catalog?$query');
      if (mounted) {
        setState(() {
          rows = (result['rows'] as List).cast<Map<String, dynamic>>();
          cursor = result['cursor'] as String;
          more = result['has_more'] == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([
    Map<String, dynamic>? row,
    bool newVariant = false,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CatalogEditor(
        api: widget.api,
        storeId: widget.storeId,
        deviceId: widget.deviceId,
        userId: widget.userId,
        row: row,
        newVariant: newVariant,
      ),
    );
    if (saved == true && mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 250,
              child: TextField(
                controller: search,
                onSubmitted: (_) => load(),
                decoration: const InputDecoration(
                  labelText: 'Tên, SKU, mã vạch, size, màu',
                ),
              ),
            ),
            FilledButton(
              onPressed: busy ? null : () => load(),
              child: const Text('Tìm sản phẩm'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => edit(),
              child: const Text('Thêm sản phẩm'),
            ),
            FilterChip(
              label: const Text('Gồm hàng ngừng bán'),
              selected: inactive,
              onSelected: busy
                  ? null
                  : (v) {
                      setState(() => inactive = v);
                      load();
                    },
            ),
          ],
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(error, style: const TextStyle(color: Colors.red)),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final r = rows[i];
            return ListTile(
              title: Text('${r['name']} · ${r['size']} · ${r['color']}'),
              subtitle: Text(
                '${r['sku']} · ${formatWholeVnd(BigInt.from(r['price'] as int))} đ\nTồn ${r['quantity']} · Cảnh báo ≤ ${r['low_stock_threshold']}${r['active'] == 0 ? ' · Ngừng bán' : ''}',
              ),
              onTap: () => edit(r),
              trailing: IconButton(
                tooltip: 'Thêm biến thể cùng sản phẩm',
                onPressed: () => edit(r, true),
                icon: const Icon(Icons.add),
              ),
            );
          },
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Danh mục dùng chung · Tồn và ngưỡng theo cửa hàng · Chỉ lưu khi online. Có thể cần Trang tiếp khi tìm kiếm chưa có kết quả.',
        ),
      ),
      SafeArea(
        child: OutlinedButton(
          onPressed: more && !busy ? () => load(next: true) : null,
          child: const Text('Trang tiếp'),
        ),
      ),
    ],
  );
}

class _CatalogEditor extends StatefulWidget {
  const _CatalogEditor({
    required this.api,
    required this.storeId,
    required this.deviceId,
    required this.userId,
    this.row,
    this.newVariant = false,
  });
  final CloudApi api;
  final String storeId, deviceId, userId;
  final Map<String, dynamic>? row;
  final bool newVariant;
  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  final fields = <String, TextEditingController>{};
  late final String productId =
          widget.row?['product_id'] as String? ?? const Uuid().v7(),
      variantId = widget.newVariant
          ? const Uuid().v7()
          : widget.row?['id'] as String? ?? const Uuid().v7();
  late bool active = widget.newVariant || widget.row?['active'] != 0;
  bool busy = false;
  String? error;
  Map<String, Object?>? pending;
  String? fingerprint;
  static const labels = {
    'name': 'Tên sản phẩm',
    'category': 'Loại đồ',
    'gender': 'Giới tính',
    'school_level': 'Cấp học',
    'school_year': 'Năm học',
    'size': 'Size',
    'color': 'Màu',
    'unit': 'Đơn vị',
    'sku': 'SKU',
    'barcode': 'Mã vạch',
    'price': 'Giá bán (VND)',
    'cost': 'Giá vốn (VND)',
    'low_stock_threshold': 'Ngưỡng cảnh báo cửa hàng',
    'reason': 'Lý do thay đổi',
  };
  @override
  void initState() {
    super.initState();
    final defaults = {
      'category': 'Áo sơ mi',
      'gender': 'Unisex',
      'school_level': 'Tiểu học',
      'school_year': '2026–2027',
      'unit': 'cái',
      'price': '0',
      'cost': '0',
      'low_stock_threshold': '5',
    };
    for (final key in labels.keys) {
      final clear =
          widget.newVariant &&
          ['size', 'color', 'sku', 'barcode'].contains(key);
      fields[key] = TextEditingController(
        text: clear ? '' : widget.row?[key]?.toString() ?? defaults[key] ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    try {
      final input = fields.map((k, v) => MapEntry(k, v.text.trim()));
      for (final key in labels.keys.where((k) => k != 'barcode')) {
        if (input[key]!.isEmpty) {
          throw ArgumentError('Cần nhập ${labels[key]}.');
        }
      }
      final numbers = <String, int>{};
      for (final key in ['price', 'cost', 'low_stock_threshold']) {
        final value = int.tryParse(input[key]!);
        if (value == null || value < 0 || value > 9007199254740991) {
          throw ArgumentError('${labels[key]} phải là số nguyên không âm.');
        }
        numbers[key] = value;
      }
      final currentFingerprint = jsonEncode({...input, 'active': active});
      if (pending == null || fingerprint != currentFingerprint) {
        final id = const Uuid().v7(),
            stamp = DateTime.now().toUtc().toIso8601String(),
            thresholdId = const Uuid().v7();
        final key = '$stamp|${widget.deviceId}|$id';
        final p = <String, Object?>{
          'id': productId,
          for (final key in [
            'name',
            'category',
            'gender',
            'school_level',
            'school_year',
          ])
            key: input[key],
          'image_path': widget.row?['image_path'],
          'active': widget.row?['product_active'] ?? 1,
          'updated_at': stamp,
          'version': (widget.row?['product_version'] as int? ?? 0) + 1,
          'lww_key': key,
        };
        final v = <String, Object?>{
          'id': variantId,
          'product_id': productId,
          for (final key in ['sku', 'size', 'color', 'unit']) key: input[key],
          'barcode': input['barcode']!.isEmpty ? null : input['barcode'],
          'cost': numbers['cost'],
          'price': numbers['price'],
          'active': active ? 1 : 0,
          'updated_at': stamp,
          'version': widget.newVariant
              ? 1
              : (widget.row?['version'] as int? ?? 0) + 1,
          'lww_key': key,
        };
        pending = {
          'id': id,
          'reason': input['reason'],
          'records': [
            {'table': 'products', 'row': p},
            {'table': 'product_variants', 'row': v},
            {
              'table': 'stock_threshold_rules',
              'row': {
                'id': thresholdId,
                'store_id': widget.storeId,
                'device_id': widget.deviceId,
                'user_id': widget.userId,
                'variant_id': variantId,
                'threshold': numbers['low_stock_threshold'],
                'version_key':
                    '${DateTime.fromMillisecondsSinceEpoch(DateTime.parse(stamp).millisecondsSinceEpoch, isUtc: true).toIso8601String()}|${widget.deviceId}|$thresholdId',
                'created_at': stamp,
              },
            },
          ],
        };
        fingerprint = currentFingerprint;
      }
      setState(() {
        busy = true;
        error = null;
      });
      final ack = await widget.api.send('/web/catalog', body: pending);
      if ((ack['acknowledged'] as List?)?.contains(pending!['id']) != true) {
        throw StateError(
          'Cloud chưa xác nhận thay đổi. Có thể bấm Lưu online để thử lại.',
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.newVariant
          ? 'Thêm biến thể'
          : widget.row == null
          ? 'Thêm sản phẩm'
          : 'Sửa sản phẩm / biến thể',
    ),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tên, loại đồ, cấp học và năm học áp dụng cho các biến thể cùng sản phẩm tại mọi cửa hàng.',
            ),
            for (final entry in labels.entries)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: fields[entry.key],
                  enabled: !busy,
                  keyboardType:
                      [
                        'price',
                        'cost',
                        'low_stock_threshold',
                      ].contains(entry.key)
                      ? TextInputType.number
                      : TextInputType.text,
                  decoration: InputDecoration(labelText: entry.value),
                ),
              ),
            SwitchListTile(
              title: const Text('Đang bán biến thể'),
              value: active,
              onChanged: busy ? null : (v) => setState(() => active = v),
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
        child: Text(busy ? 'Đang lưu…' : 'Lưu online'),
      ),
    ],
  );
}
