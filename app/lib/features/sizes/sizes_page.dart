import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../tailoring/tailoring_rule.dart'
    show measurementInput, measurementText;
import 'size_rule.dart';
import 'size_service.dart';

class SizesPage extends StatefulWidget {
  const SizesPage({super.key, required this.service});
  final LocalService service;
  @override
  State<SizesPage> createState() => _SizesPageState();
}

class _SizesPageState extends State<SizesPage> {
  final height = TextEditingController(), weight = TextEditingController();
  List<Map<String, Object?>> rules = [];
  String? selected, error;
  List<String>? suggestions;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    height.dispose();
    weight.dispose();
    super.dispose();
  }

  bool get canEdit => widget.service.session!.can(Permission.catalog);
  Map<String, Object?>? get current =>
      rules.where((r) => r['id'] == selected).firstOrNull;
  Future<void> load() async {
    try {
      final data = await widget.service.sizeRules();
      if (mounted) {
        setState(() {
          rules = data.where((r) => r['active'] == 1 || canEdit).toList();
          selected = rules.any((r) => r['id'] == selected)
              ? selected
              : rules.firstOrNull?['id'] as String?;
          error = null;
          suggestions = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> edit([Map<String, Object?>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SizeEditor(service: widget.service, row: row),
    );
    if (saved == true && mounted) await load();
  }

  void suggest() {
    try {
      if (current == null || current!['active'] != 1) {
        throw StateError('Chọn bảng size đang áp dụng.');
      }
      final result = SizeRule.parse(current!['config_json'] as String).suggest(
        measurementInput(height.text, 'height'),
        measurementInput(weight.text, 'weight'),
      );
      setState(() {
        suggestions = result;
        error = null;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        suggestions = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Bảng quy đổi · gợi ý size',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      const Text(
        'Chiều cao và cân nặng được đối chiếu với bảng do cửa hàng cấu hình. Nếu nhiều size phù hợp, hiển thị tất cả để chọn khi thử đồ.',
      ),
      const SizedBox(height: 16),
      if (canEdit)
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: () => edit(),
              child: const Text('Thêm bảng size'),
            ),
            if (current != null)
              OutlinedButton(
                onPressed: () => edit(current),
                child: const Text('Sửa bảng size'),
              ),
          ],
        ),
      const SizedBox(height: 16),
      if (rules.isEmpty)
        const Text(
          'Chưa có bảng size. Quản lý cần nhập khoảng chiều cao/cân nặng cho từng size.',
        ),
      if (rules.isNotEmpty)
        DropdownButtonFormField<String>(
          key: ValueKey(selected),
          isExpanded: true,
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Bảng size'),
          items: [
            for (final r in rules)
              DropdownMenuItem(
                value: r['id'] as String,
                child: Text(
                  '${r['name']}${r['active'] == 0 ? ' · Ngừng áp dụng' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            selected = v;
            suggestions = null;
          }),
        ),
      if (current != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Áp dụng: ${current!['product_name'] ?? 'Các sản phẩm dùng chung bảng này'}',
          ),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: height,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Chiều cao (cm)'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Cân nặng (kg)'),
              ),
            ),
            FilledButton(onPressed: suggest, child: const Text('Gợi ý size')),
          ],
        ),
        if (suggestions != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: suggestions!.isEmpty
                ? const Text(
                    'Không có size trong khoảng đã cấu hình. Kiểm tra số đo hoặc chọn đơn may riêng.',
                  )
                : Wrap(
                    spacing: 8,
                    children: [
                      const Text('Size phù hợp:'),
                      for (final s in suggestions!) Chip(label: Text(s)),
                    ],
                  ),
          ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Size')),
              DataColumn(label: Text('Chiều cao (cm)')),
              DataColumn(label: Text('Cân nặng (kg)')),
            ],
            rows: [
              for (final r in SizeRule.parse(
                current!['config_json'] as String,
              ).rows)
                DataRow(
                  cells: [
                    DataCell(Text(r['size'] as String)),
                    DataCell(
                      Text(
                        '${measurementText(r['height_min'] as int, 'height')}–${measurementText(r['height_max'] as int, 'height')}',
                      ),
                    ),
                    DataCell(
                      Text(
                        '${measurementText(r['weight_min'] as int, 'weight')}–${measurementText(r['weight_max'] as int, 'weight')}',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(error!, style: const TextStyle(color: Colors.red)),
        ),
    ],
  );
}

class _BandInputs {
  _BandInputs([Map<String, Object?>? band])
    : fields = {
        for (final k in [
          'size',
          'height_min',
          'height_max',
          'weight_min',
          'weight_max',
        ])
          k: TextEditingController(
            text: band == null
                ? ''
                : k == 'size'
                ? band[k] as String
                : measurementText(
                    band[k] as int,
                    k.startsWith('height') ? 'height' : 'weight',
                  ),
          ),
      };
  final Map<String, TextEditingController> fields;
  Map<String, Object?> values() => {
    for (final e in fields.entries)
      e.key: e.key == 'size'
          ? e.value.text.trim()
          : measurementInput(
              e.value.text,
              e.key.startsWith('height') ? 'height' : 'weight',
            ),
  };
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
  }
}

class _SizeEditor extends StatefulWidget {
  const _SizeEditor({required this.service, this.row});
  final LocalService service;
  final Map<String, Object?>? row;
  @override
  State<_SizeEditor> createState() => _SizeEditorState();
}

class _SizeEditorState extends State<_SizeEditor> {
  late final name = TextEditingController(
    text: widget.row?['name'] as String? ?? '',
  );
  late final bands = widget.row == null
      ? [_BandInputs()]
      : SizeRule.parse(widget.row!['config_json'] as String).rows
            .map(_BandInputs.new)
            .toList();
  final retired = <_BandInputs>[];
  late String product = widget.row?['product_id'] as String? ?? '';
  late bool active = widget.row?['active'] != 0;
  bool busy = false;
  String? error;
  List<Map<String, Object?>> products = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final catalog = await widget.service.catalog();
      final data = {
        for (final v in catalog)
          v['product_id'] as String: {'id': v['product_id'], 'name': v['name']},
      };
      if (product.isNotEmpty && !data.containsKey(product)) {
        data[product] = {
          'id': product,
          'name': widget.row?['product_name'] ?? 'Sản phẩm đã ngừng bán',
        };
      }
      if (mounted) setState(() => products = data.values.toList());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    name.dispose();
    for (final b in [...bands, ...retired]) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.service.saveSizeRule(
        id: widget.row?['id'] as String?,
        name: name.text,
        productId: product.isEmpty ? null : product,
        rule: SizeRule(bands.map((b) => b.values()).toList()),
        active: active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.row == null ? 'Thêm bảng size' : 'Sửa bảng size'),
    content: SizedBox(
      width: 760,
      height: 520,
      child: Column(
        children: [
          TextField(
            controller: name,
            enabled: !busy,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Tên bảng size'),
          ),
          if (products.isNotEmpty || product.isEmpty)
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: product,
              decoration: const InputDecoration(labelText: 'Sản phẩm áp dụng'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Dùng chung nhiều sản phẩm'),
                ),
                for (final p in products)
                  DropdownMenuItem(
                    value: p['id'] as String,
                    child: Text(
                      p['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy ? null : (v) => setState(() => product = v!),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Đang áp dụng'),
            value: active,
            onChanged: busy ? null : (v) => setState(() => active = v),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final band in bands)
                  Card(
                    key: ObjectKey(band),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final entry in <String, String>{
                            'size': 'Size',
                            'height_min': 'Cao từ (cm)',
                            'height_max': 'Cao đến (cm)',
                            'weight_min': 'Nặng từ (kg)',
                            'weight_max': 'Nặng đến (kg)',
                          }.entries)
                            SizedBox(
                              width: 120,
                              child: TextField(
                                controller: band.fields[entry.key],
                                enabled: !busy,
                                decoration: InputDecoration(
                                  labelText: entry.value,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Bỏ dòng size',
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    bands.remove(band);
                                    retired.add(band);
                                  }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          TextButton.icon(
            onPressed: busy || bands.length >= 50
                ? null
                : () => setState(() => bands.add(_BandInputs())),
            icon: const Icon(Icons.add),
            label: const Text('Thêm dòng size'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Quay lại'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Đang lưu…' : 'Lưu bảng size'),
      ),
    ],
  );
}
