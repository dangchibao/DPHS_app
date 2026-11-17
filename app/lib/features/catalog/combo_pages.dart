import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../pos/pricing.dart';
import 'combo_service.dart';

final _vnd = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: '₫',
  decimalDigits: 0,
);

class CombosPage extends StatefulWidget {
  const CombosPage({super.key, required this.service});
  final LocalService service;
  @override
  State<CombosPage> createState() => _CombosPageState();
}

class _PartEditor {
  _PartEditor(this.productId, int count)
    : quantity = TextEditingController(text: '$count');
  String? productId;
  final TextEditingController quantity;
}

class _CombosPageState extends State<CombosPage> {
  late Future<Map<String, List<Map<String, Object?>>>> data;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    data = load();
  }

  Future<Map<String, List<Map<String, Object?>>>> load() async {
    final rules = await widget.service.comboRules();
    final products = await widget.service.db.rows(
      'SELECT id,name,active FROM products ORDER BY name',
    );
    return {'rules': rules, 'products': products};
  }

  Future<void> edit(
    List<Map<String, Object?>> products, [
    Map<String, Object?>? row,
  ]) async {
    final name = TextEditingController(text: row?['name'] as String? ?? ''),
        price = TextEditingController(text: '${row?['price'] ?? 0}');
    final parts = <_PartEditor>[
      if (row != null)
        for (final raw in jsonDecode(row['items_json'] as String) as List)
          _PartEditor(
            (raw as Map)['product_id'] as String,
            raw['quantity'] as int,
          )
      else
        _PartEditor(null, 1),
    ];
    final owned = [...parts];
    var active = row?['active'] != 0, saving = false;
    String? error;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text(row == null ? 'Tạo combo đồng phục' : 'Cập nhật combo'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: 'Tên combo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: price,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá cả bộ (VND)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Món thành phần — size/màu chọn tại POS'),
                    ),
                    for (final part in parts)
                      Padding(
                        key: ValueKey(part),
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: part.productId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Sản phẩm',
                                ),
                                items: [
                                  for (final p in products)
                                    DropdownMenuItem(
                                      value: p['id'] as String,
                                      child: Text(
                                        '${p['name']}${p['active'] == 0 ? ' (ngừng bán)' : ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: saving
                                    ? null
                                    : (v) => part.productId = v,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 76,
                              child: TextField(
                                controller: part.quantity,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'SL/bộ',
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: saving
                                  ? null
                                  : () => setDialog(() => parts.remove(part)),
                              tooltip: 'Bỏ món',
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    TextButton.icon(
                      onPressed: saving || parts.length >= 20
                          ? null
                          : () => setDialog(() {
                              final part = _PartEditor(null, 1);
                              owned.add(part);
                              parts.add(part);
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm món thành phần'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      onChanged: saving
                          ? null
                          : (v) => setDialog(() => active = v),
                      title: const Text('Đang bán combo'),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog),
                child: const Text('Đóng'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialog(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final value = int.tryParse(price.text.trim());
                          if (value == null ||
                              parts.any(
                                (p) =>
                                    p.productId == null ||
                                    int.tryParse(p.quantity.text.trim()) ==
                                        null,
                              )) {
                            throw ArgumentError(
                              'Nhập giá, chọn sản phẩm và số lượng nguyên.',
                            );
                          }
                          await widget.service.saveCombo(
                            id: row?['id'] as String?,
                            name: name.text,
                            price: value,
                            parts: parts
                                .map(
                                  (p) => ComboPart(
                                    p.productId!,
                                    int.parse(p.quantity.text.trim()),
                                  ),
                                )
                                .toList(),
                            active: active,
                          );
                          if (dialog.mounted) {
                            Navigator.pop(dialog);
                          }
                          if (mounted) {
                            setState(refresh);
                          }
                        } catch (e) {
                          if (dialog.mounted) {
                            setDialog(() {
                              error = e.toString().replaceFirst(
                                'Bad state: ',
                                '',
                              );
                              saving = false;
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Đang lưu…' : 'Lưu combo'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      price.dispose();
      for (final p in owned) {
        p.quantity.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: FutureBuilder(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!['rules']!,
            products = snapshot.data!['products']!;
        final names = {for (final p in products) p['id']: p['name']};
        final canEdit =
            widget.service.session?.can(Permission.catalog) ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Giá riêng cho cả bộ, tồn trừ từng món.'),
                ),
                IconButton(
                  onPressed: () => setState(refresh),
                  icon: const Icon(Icons.refresh),
                ),
                if (canEdit)
                  FilledButton.icon(
                    onPressed: () => edit(products),
                    icon: const Icon(Icons.add),
                    label: const Text('Tạo combo'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Chưa có combo.'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index], rule = comboFromRow(row);
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.layers_outlined),
                            title: Text(
                              '${rule.name} · ${_vnd.format(rule.price)}',
                            ),
                            subtitle: Text(
                              '${rule.parts.map((p) => '${names[p.productId] ?? 'Sản phẩm'} ×${p.quantity}').join(' · ')}${row['active'] == 0 ? '\nNgừng bán combo' : ''}',
                            ),
                            trailing: canEdit
                                ? IconButton(
                                    onPressed: () => edit(products, row),
                                    tooltip: 'Chỉnh sửa',
                                    icon: const Icon(Icons.edit_outlined),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

Future<ComboSelection?> pickCombo(
  BuildContext context,
  LocalService service,
  List<Map<String, Object?>> variants,
) async {
  service.require(Permission.sell);
  final rows = await service.comboRules(activeOnly: true);
  if (!context.mounted) {
    return null;
  }
  final chosen = await showDialog<ComboDefinition>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Chọn combo đồng phục'),
      children: [
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Chưa có combo đang bán.'),
          ),
        for (final row in rows)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, comboFromRow(row)),
            child: ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: Text(row['name'] as String),
              subtitle: Text('${_vnd.format(row['price'])} / bộ'),
            ),
          ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) {
    return null;
  }
  final choices = [
    for (final part in chosen.parts)
      variants.where((v) => v['product_id'] == part.productId).toList(),
  ];
  final picks = <String?>[
    for (final values in choices)
      values.isEmpty ? null : values.first['id'] as String,
  ];
  final quantity = TextEditingController(text: '1');
  String? error;
  try {
    return await showDialog<ComboSelection>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(chosen.name),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_vnd.format(chosen.price)} / bộ',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Số bộ'),
                  ),
                  for (var i = 0; i < chosen.parts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: DropdownButtonFormField<String>(
                        initialValue: picks[i],
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText:
                              '${choices[i].firstOrNull?['name'] ?? 'Món ${i + 1}'} ×${chosen.parts[i].quantity}/bộ',
                        ),
                        items: [
                          for (final v in choices[i])
                            DropdownMenuItem(
                              value: v['id'] as String,
                              child: Text(
                                'Size ${v['size']} · ${v['color']} · Còn ${v['device_available']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => picks[i] = v,
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: () {
                final count = int.tryParse(quantity.text.trim());
                if (count == null ||
                    count < 1 ||
                    count > 100000 ||
                    picks.any((id) => id == null) ||
                    chosen.parts.any((p) => p.quantity * count > 100000)) {
                  setDialog(
                    () => error = 'Chọn đủ size/màu và số bộ hợp lệ; tối đa 100.000 món mỗi biến thể.',
                  );
                  return;
                }
                Navigator.pop(
                  dialog,
                  ComboSelection(
                    rule: chosen,
                    picks: picks.cast<String>().toList(),
                    quantity: count,
                  ),
                );
              },
              child: const Text('Thêm đủ món vào giỏ'),
            ),
          ],
        ),
      ),
    );
  } finally {
    quantity.dispose();
  }
}
