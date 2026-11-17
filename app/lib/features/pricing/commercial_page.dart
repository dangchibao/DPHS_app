import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../schools/school_service.dart';
import 'commercial_rule.dart';
import 'commercial_service.dart';

int percentBasisPoints(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(text)) {
    throw ArgumentError('Phần trăm có tối đa 2 số lẻ.');
  }
  final parts = text.split('.');
  final value =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  if (value < 1 || value > 10000) {
    throw ArgumentError('Giảm từ 0,01% đến 100%.');
  }
  return value;
}

String _percent(int value) =>
    '${value ~/ 100}${value % 100 == 0 ? '' : '.${(value % 100).toString().padLeft(2, '0')}'}';

Future<void> _dialog({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final route = DialogRoute<void>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
}

class _PriceEditor {
  _PriceEditor(this.variant, int value)
    : price = TextEditingController(text: '$value');
  String? variant;
  final TextEditingController price;
}

class CommercialPage extends StatefulWidget {
  const CommercialPage({super.key, required this.service});
  final LocalService service;
  @override
  State<CommercialPage> createState() => _CommercialPageState();
}

class _CommercialPageState extends State<CommercialPage> {
  late Future<Map<String, List<Map<String, Object?>>>> future;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    future = load();
  }

  Future<Map<String, List<Map<String, Object?>>>> load() async {
    final rules = await widget.service.commercialRules();
    return {
      'rules': rules,
      'schools': (await widget.service.schoolDirectory())['schools']!,
      'variants': await widget.service.db.rows(
        'SELECT v.id,p.name,v.size,v.color,v.price FROM product_variants v JOIN products p ON p.id=v.product_id ORDER BY p.name,v.size,v.color',
      ),
      'dealers': await widget.service.db.rows(
        "SELECT * FROM customers WHERE store_id=? AND kind='dealer' ORDER BY name",
        [widget.service.storeId],
      ),
    };
  }

  void message(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> dealer([Map<String, Object?>? row]) async {
    final name = TextEditingController(text: row?['name'] as String? ?? ''),
        phone = TextEditingController(text: row?['phone'] as String? ?? '');
    var saving = false;
    String? error;
    try {
      await _dialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text(row == null ? 'Thêm đại lý' : 'Sửa đại lý'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Tên đại lý'),
                  ),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Điện thoại'),
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialog(() => saving = true);
                        try {
                          await widget.service.saveDealer(
                            id: row?['id'] as String?,
                            name: name.text,
                            phone: phone.text,
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          setDialog(() {
                            error = e.toString();
                            saving = false;
                          });
                        }
                      },
                child: const Text('Lưu'),
              ),
            ],
          ),
        ),
      );
      if (mounted) setState(refresh);
    } finally {
      name.dispose();
      phone.dispose();
    }
  }

  Future<void> edit(
    Map<String, List<Map<String, Object?>>> data, [
    Map<String, Object?>? row,
  ]) async {
    final config = row == null
        ? CommercialRule.defaults()
        : Map<String, Object?>.from(
            jsonDecode(row['config_json'] as String) as Map,
          );
    var kind = row?['kind'] as String? ?? 'promotion',
        mode = config['discount_type'] as String;
    if (mode == 'none') mode = 'fixed';
    final name = TextEditingController(text: row?['name'] as String? ?? ''),
        value = TextEditingController(
          text: mode == 'percent'
              ? _percent(config['value'] as int)
              : '${config['value']}',
        ),
        minTotal = TextEditingController(text: '${config['min_total']}'),
        minQuantity = TextEditingController(text: '${config['min_quantity']}'),
        voucher = TextEditingController(text: config['voucher'] as String);
    final prices = <_PriceEditor>[
      for (final e in (config['prices'] as Map).entries)
        _PriceEditor(e.key as String, e.value as int),
    ];
    final owned = [...prices];
    var school = config['school_id'] as String? ?? '',
        customer = config['customer_kind'] as String? ?? '',
        active = row?['active'] != 0,
        allowCombo = config['allow_combo'] == true,
        allowPriceList = config['allow_price_list'] == true,
        saving = false;
    String? error;
    DateTime? start = config['starts_at'] == null
            ? null
            : DateTime.parse(config['starts_at'] as String)
                  .toUtc()
                  .add(const Duration(hours: 7)),
        end = config['ends_at'] == null
            ? null
            : DateTime.parse(config['ends_at'] as String)
                  .toUtc()
                  .add(const Duration(hours: 7))
                  .subtract(const Duration(days: 1));
    String? utcDate(DateTime? date, {bool next = false}) => date == null
        ? null
        : DateTime.utc(
            date.year,
            date.month,
            date.day + (next ? 1 : 0),
          ).subtract(const Duration(hours: 7)).toIso8601String();
    try {
      await _dialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text(
              row == null
                  ? 'Thêm bảng giá / khuyến mãi'
                  : 'Sửa bảng giá / khuyến mãi',
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: name,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Tên chương trình / bảng giá',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Loại'),
                      items: const [
                        DropdownMenuItem(
                          value: 'price_list',
                          child: Text('Bảng giá riêng'),
                        ),
                        DropdownMenuItem(
                          value: 'promotion',
                          child: Text('Khuyến mãi / voucher'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) => setDialog(() => kind = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: school,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Trường áp dụng',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Tất cả trường / khách'),
                        ),
                        for (final s in data['schools']!)
                          DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text(
                              s['name'] as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: saving ? null : (v) => school = v!,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: customer,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Nhóm khách',
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Tất cả')),
                        DropdownMenuItem(
                          value: 'parent',
                          child: Text('Phụ huynh'),
                        ),
                        DropdownMenuItem(
                          value: 'school',
                          child: Text('Nhà trường'),
                        ),
                        DropdownMenuItem(
                          value: 'dealer',
                          child: Text('Đại lý'),
                        ),
                      ],
                      onChanged: saving ? null : (v) => customer = v!,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: start ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (date != null) {
                                    setDialog(() => start = date);
                                  }
                                },
                          child: Text(
                            start == null
                                ? 'Từ ngày: không giới hạn'
                                : 'Từ ${DateFormat('dd/MM/yyyy').format(start!)}',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: end ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (date != null) setDialog(() => end = date);
                                },
                          child: Text(
                            end == null
                                ? 'Đến ngày: không giới hạn'
                                : 'Đến hết ${DateFormat('dd/MM/yyyy').format(end!)}',
                          ),
                        ),
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => setDialog(() {
                                  start = null;
                                  end = null;
                                }),
                          child: const Text('Bỏ giới hạn ngày'),
                        ),
                      ],
                    ),
                    TextField(
                      controller: minQuantity,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Số món tối thiểu',
                      ),
                    ),
                    TextField(
                      controller: minTotal,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Tiền hàng tối thiểu (VND)',
                      ),
                    ),
                    if (kind == 'promotion') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: mode,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'fixed',
                            child: Text('Giảm số tiền VND'),
                          ),
                          DropdownMenuItem(
                            value: 'percent',
                            child: Text('Giảm phần trăm'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialog(() {
                                mode = v!;
                                value.text = mode == 'percent' ? '10' : '10000';
                              }),
                      ),
                      TextField(
                        controller: value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: mode == 'percent'
                              ? 'Mức giảm (%)'
                              : 'Mức giảm (VND)',
                        ),
                      ),
                      TextField(
                        controller: voucher,
                        maxLength: 32,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Mã voucher (để trống nếu không cần mã)',
                          helperText: 'Mã dùng nhiều lần, theo thời gian và điều kiện đơn.',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: allowPriceList,
                        onChanged: saving
                            ? null
                            : (v) => setDialog(() => allowPriceList = v!),
                        title: const Text('Cho phép cộng với bảng giá riêng'),
                      ),
                      const Text(
                        'Mỗi đơn chỉ chọn một chương trình. Không cộng thêm giảm thủ công.',
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Giá riêng theo biến thể; món không khai báo giữ giá chung.',
                      ),
                      for (final p in prices)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: p.variant,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Sản phẩm · size · màu',
                                ),
                                items: [
                                  for (final v in data['variants']!)
                                    DropdownMenuItem(
                                      value: v['id'] as String,
                                      child: Text(
                                        '${v['name']} · ${v['size']} · ${v['color']}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: saving ? null : (v) => p.variant = v,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: p.price,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'Giá riêng (VND)',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: saving
                                        ? null
                                        : () =>
                                              setDialog(() => prices.remove(p)),
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Bỏ dòng giá',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: saving || prices.length >= 100
                            ? null
                            : () => setDialog(() {
                                final p = _PriceEditor(null, 0);
                                prices.add(p);
                                owned.add(p);
                              }),
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm biến thể'),
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allowCombo,
                      onChanged: saving
                          ? null
                          : (v) => setDialog(() => allowCombo = v!),
                      title: const Text('Cho phép áp dụng khi đơn có combo'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      onChanged: saving
                          ? null
                          : (v) => setDialog(() => active = v),
                      title: const Text('Đang áp dụng'),
                    ),
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
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
                          final entries = <String, int>{};
                          if (kind == 'price_list') {
                            for (final p in prices) {
                              if (p.variant == null ||
                                  entries.containsKey(p.variant)) {
                                throw StateError(
                                  'Chọn biến thể, mỗi biến thể một dòng.',
                                );
                              }
                              entries[p.variant!] = int.parse(p.price.text);
                            }
                          }
                          await widget.service.saveCommercialRule(
                            id: row?['id'] as String?,
                            name: name.text,
                            kind: kind,
                            active: active,
                            config: {
                              'school_id': school.isEmpty ? null : school,
                              'customer_kind': customer.isEmpty
                                  ? null
                                  : customer,
                              'starts_at': utcDate(start),
                              'ends_at': utcDate(end, next: true),
                              'min_total': int.parse(minTotal.text),
                              'min_quantity': int.parse(minQuantity.text),
                              'allow_combo': allowCombo,
                              'allow_price_list':
                                  kind == 'promotion' && allowPriceList,
                              'prices': entries,
                              'discount_type': kind == 'price_list'
                                  ? 'none'
                                  : mode,
                              'value': kind == 'price_list'
                                  ? 0
                                  : mode == 'percent'
                                  ? percentBasisPoints(value.text)
                                  : int.parse(value.text),
                              'voucher': kind == 'price_list'
                                  ? ''
                                  : voucher.text.trim().toUpperCase(),
                            },
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          setDialog(() {
                            error = e.toString().replaceFirst(
                              'Bad state: ',
                              '',
                            );
                            saving = false;
                          });
                        }
                      },
                child: Text(saving ? 'Đang lưu…' : 'Lưu'),
              ),
            ],
          ),
        ),
      );
      if (mounted) setState(refresh);
    } finally {
      for (final c in [name, value, minTotal, minQuantity, voucher]) {
        c.dispose();
      }
      for (final p in owned) {
        p.price.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => edit(data),
                icon: const Icon(Icons.add),
                label: const Text('Bảng giá / khuyến mãi'),
              ),
              OutlinedButton.icon(
                onPressed: () => dealer(),
                icon: const Icon(Icons.storefront),
                label: const Text('Thêm đại lý'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final row in data['rules']!)
            Card(
              child: ListTile(
                title: Text(
                  '${row['name']}${row['active'] == 0 ? ' · Ngừng áp dụng' : ''}',
                ),
                subtitle: Text(
                  row['kind'] == 'price_list'
                      ? 'Bảng giá riêng'
                      : 'Khuyến mãi / voucher',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => edit(data, row),
              ),
            ),
          const SizedBox(height: 16),
          Text('Đại lý', style: Theme.of(context).textTheme.titleLarge),
          for (final row in data['dealers']!)
            ListTile(
              title: Text(row['name'] as String),
              subtitle: Text(row['phone'] as String),
              onTap: () => dealer(row),
            ),
          if (data['rules']!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Chưa có quy tắc. Giá bán chung vẫn được áp dụng.'),
            ),
        ],
      );
    },
  );
}
