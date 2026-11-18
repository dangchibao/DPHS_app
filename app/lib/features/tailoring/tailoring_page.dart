import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../audit/document_audit_button.dart';
import '../../core/auth/permissions.dart';
import '../pos/pricing.dart';
import '../pos/sales_service.dart';
import '../pos/document_pdf.dart';
import 'tailoring_rule.dart';
import 'tailoring_service.dart';

final _vnd = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: '₫',
  decimalDigits: 0,
);
Future<void> _form({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<void>(
    context: context,
    builder: builder,
    barrierDismissible: false,
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
}

class _OptionEditor {
  _OptionEditor(this.id, String label, int value)
    : name = TextEditingController(text: label),
      amount = TextEditingController(text: '$value');
  final String id;
  final TextEditingController name, amount;
}

class TailoringPage extends StatefulWidget {
  const TailoringPage({super.key, required this.service});
  final LocalService service;
  @override
  State<TailoringPage> createState() => _TailoringPageState();
}

class _TailoringPageState extends State<TailoringPage> {
  late Future<Map<String, List<Map<String, Object?>>>> future;
  int? status;
  String search = '';
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    future = load();
  }

  Future<Map<String, List<Map<String, Object?>>>> load() async => {
    'orders': await widget.service.tailoringOrders(),
    'rules': await widget.service.tailoringRules(),
    'products': await widget.service.catalog(),
    'customers': await widget.service.db.rows(
      'SELECT id,name,phone,kind FROM customers WHERE store_id=? ORDER BY name',
      [widget.service.storeId],
    ),
    'students': await widget.service.db.rows(
      'SELECT st.id,st.name,st.student_code,cl.school_id,c.name AS parent_name,c.phone FROM students st JOIN school_classes cl ON cl.id=st.class_id AND cl.store_id=st.store_id JOIN customers c ON c.id=st.customer_id AND c.store_id=st.store_id WHERE st.store_id=? AND st.active=1 AND cl.active=1 ORDER BY st.name',
      [widget.service.storeId],
    ),
  };
  void message(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> rules(List<Map<String, Object?>> data) async {
    await _form(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bảng phụ thu may'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in data)
                  ListTile(
                    title: Text(
                      '${row['name']}${row['active'] == 0 ? ' · Ngừng áp dụng' : ''}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      Navigator.pop(context);
                      await editRule(row);
                    },
                  ),
                if (data.isEmpty)
                  const Text('Tạo bảng phụ thu trước khi nhận đơn may.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              editRule();
            },
            child: const Text('Thêm bảng phụ thu'),
          ),
        ],
      ),
    );
  }

  Future<void> editRule([Map<String, Object?>? row]) async {
    final config = row == null
            ? TailoringRule.defaults()
            : Map<String, Object?>.from(
                jsonDecode(row['config_json'] as String) as Map,
              ),
        name = TextEditingController(text: row?['name'] as String? ?? ''),
        base = TextEditingController(text: '${config['base_fee']}');
    final rates = config['rates'] as Map,
        enabled = rates.keys.cast<String>().toSet();
    final thresholds = {
          for (final field in measurementLabels.keys)
            field: TextEditingController(
              text: rates.containsKey(field)
                  ? measurementText(
                      (rates[field] as Map)['threshold'] as int,
                      field,
                    )
                  : '0',
            ),
        },
        steps = {
          for (final field in measurementLabels.keys)
            field: TextEditingController(
              text: rates.containsKey(field)
                  ? measurementText((rates[field] as Map)['step'] as int, field)
                  : '1',
            ),
        },
        amounts = {
          for (final field in measurementLabels.keys)
            field: TextEditingController(
              text: rates.containsKey(field)
                  ? '${(rates[field] as Map)['amount']}'
                  : '0',
            ),
        };
    final options = [
          for (final entry in (config['options'] as Map).entries)
            _OptionEditor(
              entry.key as String,
              (entry.value as Map)['label'] as String,
              (entry.value as Map)['amount'] as int,
            ),
        ],
        owned = <_OptionEditor>[];
    owned.addAll(options);
    var active = row?['active'] != 0, saving = false;
    String? error;
    int metric(String input, String field, {bool zero = false}) =>
        zero && RegExp(r'^0([,.]0+)?$').hasMatch(input.trim())
        ? 0
        : measurementInput(input, field);
    try {
      await _form(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('Cấu hình phụ thu trên mỗi món'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: name,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Tên bảng phụ thu',
                      ),
                    ),
                    TextField(
                      controller: base,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Phụ thu cơ bản mỗi món (VND)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Mỗi phần vượt ngưỡng được làm tròn lên một bậc. Các khoản đã bật được cộng lại.',
                    ),
                    for (final field in measurementLabels.keys)
                      ExpansionTile(
                        title: Text(
                          'Theo ${measurementLabels[field]} (${field == 'weight' ? 'kg' : 'cm'})',
                        ),
                        children: [
                          CheckboxListTile(
                            title: const Text('Áp dụng phụ thu này'),
                            value: enabled.contains(field),
                            onChanged: saving
                                ? null
                                : (v) => setDialog(() {
                                    if (v!) {
                                      enabled.add(field);
                                    } else {
                                      enabled.remove(field);
                                    }
                                  }),
                          ),
                          for (final pair in [
                            (thresholds[field]!, 'Ngưỡng không phụ thu'),
                            (steps[field]!, 'Mỗi bậc vượt'),
                            (amounts[field]!, 'Tiền mỗi bậc (VND)'),
                          ])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: TextField(
                                controller: pair.$1,
                                enabled: !saving && enabled.contains(field),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(labelText: pair.$2),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Yêu cầu có phụ thu (may gấp, thêm túi, đổi cổ…)',
                    ),
                    for (final option in options)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              TextField(
                                controller: option.name,
                                enabled: !saving,
                                decoration: const InputDecoration(
                                  labelText: 'Tên yêu cầu',
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: option.amount,
                                      enabled: !saving,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'Phụ thu mỗi món (VND)',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: saving
                                        ? null
                                        : () => setDialog(
                                            () => options.remove(option),
                                          ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: saving || options.length >= 20
                          ? null
                          : () => setDialog(() {
                              final option = _OptionEditor(
                                widget.service.uuid.v7(),
                                '',
                                0,
                              );
                              options.add(option);
                              owned.add(option);
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm yêu cầu'),
                    ),
                    SwitchListTile(
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
                        setDialog(() => saving = true);
                        try {
                          await widget.service.saveTailoringRule(
                            id: row?['id'] as String?,
                            name: name.text,
                            active: active,
                            config: {
                              'base_fee': int.parse(base.text),
                              'rates': {
                                for (final field in enabled)
                                  field: {
                                    'threshold': metric(
                                      thresholds[field]!.text,
                                      field,
                                      zero: true,
                                    ),
                                    'step': metric(steps[field]!.text, field),
                                    'amount': int.parse(amounts[field]!.text),
                                  },
                              },
                              'options': {
                                for (final option in options)
                                  option.id: {
                                    'label': option.name.text.trim(),
                                    'amount': int.parse(option.amount.text),
                                  },
                              },
                            },
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          setDialog(() {
                            error = e.toString();
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
      for (final c in [
        name,
        base,
        ...thresholds.values,
        ...steps.values,
        ...amounts.values,
      ]) {
        c.dispose();
      }
      for (final option in owned) {
        option.name.dispose();
        option.amount.dispose();
      }
    }
  }

  Future<void> create(Map<String, List<Map<String, Object?>>> data) async {
    final rules = data['rules']!
            .where((r) => r['active'] == 1)
            .map(TailoringRule.fromRow)
            .toList(),
        products = data['products']!;
    if (rules.isEmpty || products.isEmpty) {
      message('Cần sản phẩm mẫu và bảng phụ thu đang áp dụng.');
      return;
    }
    var rule = rules.first,
        variant = products.first,
        method = 'cash',
        saving = false;
    final buyers = <Map<String, Object?>>[
      for (final c in data['customers']!)
        {
          'label': '${c['name']} · ${c['phone']}',
          'customer_id': c['id'],
          'name': c['name'],
          'phone': c['phone'],
        },
      for (final s in data['students']!)
        {
          'label': 'Học sinh ${s['name']} · ${s['student_code']}',
          'student_id': s['id'],
          'school_id': s['school_id'],
          'name': s['parent_name'],
          'phone': s['phone'],
        },
    ];
    Map<String, Object?>? buyer;
    final measures = {
          for (final field in measurementLabels.keys)
            field: TextEditingController(),
        },
        selected = <String>{},
        name = TextEditingController(),
        phone = TextEditingController(),
        notes = TextEditingController(),
        received = TextEditingController(text: '0'),
        quantity = TextEditingController(text: '1');
    final buyerSearch = TextEditingController(), buyerFocus = FocusNode();
    var due = widget.service.clock().toUtc().add(
      const Duration(days: 7, hours: 7),
    );
    String? error;
    final commandId = widget.service.uuid.v7();
    try {
      await _form(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) {
            int? fee, total;
            String? hint;
            try {
              fee = rule.fee({
                for (final e in measures.entries)
                  e.key: measurementInput(e.value.text, e.key),
              }, selected.toList());
              final count = int.parse(quantity.text);
              if (count < 1 || count > 100000) {
                throw ArgumentError('Số lượng 1–100000.');
              }
              total = checkedMoney(
                (BigInt.from(variant['price'] as int) + BigInt.from(fee)) *
                    BigInt.from(count),
              );
            } catch (e) {
              hint = 'Nhập đủ số đo và số lượng để tính tổng.';
            }
            return AlertDialog(
              title: const Text('Nhận đơn may riêng'),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Autocomplete<Map<String, Object?>>(
                        textEditingController: buyerSearch,
                        focusNode: buyerFocus,
                        displayStringForOption: (r) => r['label'] as String,
                        optionsBuilder: (v) => buyers
                            .where(
                              (r) => (r['label'] as String)
                                  .toLowerCase()
                                  .contains(v.text.toLowerCase()),
                            )
                            .take(30),
                        fieldViewBuilder:
                            (context, controller, focus, submit) => TextField(
                              controller: controller,
                              focusNode: focus,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                labelText: 'Tìm học sinh / khách đã có',
                              ),
                            ),
                        onSelected: (r) => setDialog(() {
                          buyer = r;
                          name.text = r['name'] as String;
                          phone.text = r['phone'] as String;
                        }),
                      ),
                      if (buyer != null)
                        InputChip(
                          label: Text(
                            'Đã chọn: ${buyer!['label']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: saving
                              ? null
                              : () => setDialog(() {
                                  buyer = null;
                                  buyerSearch.clear();
                                  name.clear();
                                  phone.clear();
                                }),
                        ),
                      TextField(
                        controller: name,
                        enabled: !saving && buyer == null,
                        decoration: const InputDecoration(
                          labelText: 'Tên khách / học sinh',
                        ),
                      ),
                      TextField(
                        controller: phone,
                        enabled: !saving && buyer == null,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Điện thoại',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: variant['id'] as String,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Mẫu sản phẩm / giá gốc',
                        ),
                        items: [
                          for (final p in products)
                            DropdownMenuItem(
                              value: p['id'] as String,
                              child: Text(
                                '${p['name']} · ${p['color']} · mẫu ${p['size']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialog(
                                () => variant = products.firstWhere(
                                  (p) => p['id'] == v,
                                ),
                              ),
                      ),
                      TextField(
                        controller: quantity,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setDialog(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Số lượng',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: rule.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Bảng phụ thu',
                        ),
                        items: [
                          for (final r in rules)
                            DropdownMenuItem(
                              value: r.id,
                              child: Text(
                                r.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialog(() {
                                rule = rules.firstWhere((r) => r.id == v);
                                selected.clear();
                              }),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Số đo riêng; chiều dài/vòng theo cm, cân nặng theo kg.',
                      ),
                      for (final e in measures.entries)
                        TextField(
                          controller: e.value,
                          enabled: !saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setDialog(() {}),
                          decoration: InputDecoration(
                            labelText:
                                '${measurementLabels[e.key]} (${e.key == 'weight' ? 'kg' : 'cm'})',
                          ),
                        ),
                      for (final e in (rule.config['options'] as Map).entries)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${(e.value as Map)['label']} · ${_vnd.format((e.value as Map)['amount'])}/món',
                          ),
                          value: selected.contains(e.key),
                          onChanged: saving
                              ? null
                              : (v) => setDialog(() {
                                  if (v!) {
                                    selected.add(e.key as String);
                                  } else {
                                    selected.remove(e.key);
                                  }
                                }),
                        ),
                      TextField(
                        controller: notes,
                        enabled: !saving,
                        maxLines: 3,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                          labelText:
                              'Yêu cầu thêm: rộng/dài hơn, bo tay, kiểu cổ…',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime(
                                    due.year,
                                    due.month,
                                    due.day,
                                  ),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null) {
                                  setDialog(() => due = date);
                                }
                              },
                        icon: const Icon(Icons.event),
                        label: Text(
                          'Hẹn trả: ${DateFormat('dd/MM/yyyy').format(due)}',
                        ),
                      ),
                      if (total != null) ...[
                        Text('Phụ thu: ${_vnd.format(fee)}/món'),
                        Text(
                          'Tổng: ${_vnd.format(total)}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ] else
                        Text(hint!),
                      TextField(
                        controller: received,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Tiền đã nhận / đặt cọc (VND)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'cash', label: Text('Tiền mặt')),
                          ButtonSegment(
                            value: 'bank',
                            label: Text('Chuyển khoản'),
                          ),
                        ],
                        selected: {method},
                        onSelectionChanged: saving
                            ? null
                            : (v) => setDialog(() => method = v.single),
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
                  onPressed: saving || total == null
                      ? null
                      : () async {
                          setDialog(() => saving = true);
                          try {
                            await widget.service.createTailoring(
                              items: [
                                CartItem(
                                  variant['id'] as String,
                                  int.parse(quantity.text),
                                ),
                              ],
                              ruleId: rule.id,
                              measurements: {
                                for (final e in measures.entries)
                                  e.key: measurementInput(e.value.text, e.key),
                              },
                              options: selected.toList(),
                              dueDate: DateFormat('yyyy-MM-dd').format(due),
                              notes: notes.text,
                              customerName: name.text,
                              phone: phone.text,
                              received: int.parse(received.text),
                              method: method,
                              commandId: commandId,
                              expectedTotal: total,
                              customerId: buyer?['customer_id'] as String?,
                              studentId: buyer?['student_id'] as String?,
                              schoolId: buyer?['school_id'] as String?,
                            );
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            setDialog(() {
                              error = e.toString();
                              saving = false;
                            });
                          }
                        },
                  child: Text(saving ? 'Đang nhận…' : 'Nhận đơn'),
                ),
              ],
            );
          },
        ),
      );
      if (mounted) setState(refresh);
    } finally {
      buyerSearch.dispose();
      buyerFocus.dispose();
      for (final c in [
        ...measures.values,
        name,
        phone,
        notes,
        received,
        quantity,
      ]) {
        c.dispose();
      }
    }
  }

  Future<void> advance(Map<String, Object?> row) async {
    final next = (row['status'] as int) + 1, reason = TextEditingController();
    var saving = false;
    String? error;
    try {
      await _form(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text('${row['code']} → ${tailoringStatuses[next]}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: reason,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú cập nhật (bắt buộc)',
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
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
                          await widget.service.advanceTailoring(
                            documentId: row['id'] as String,
                            nextStatus: next,
                            reason: reason.text,
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          setDialog(() {
                            saving = false;
                            error = e.toString();
                          });
                        }
                      },
                child: const Text('Cập nhật'),
              ),
            ],
          ),
        ),
      );
      if (mounted) setState(refresh);
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!,
          orders = data['orders']!
              .where(
                (r) =>
                    (status == null || r['status'] == status) &&
                    ('${r['code']} ${r['customer_name']} ${r['phone']}')
                        .toLowerCase()
                        .contains(search.toLowerCase()),
              )
              .toList();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.service.session!.can(Permission.sell))
                FilledButton.icon(
                  onPressed: () => create(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Nhận đơn may'),
                ),
              if (widget.service.session!.can(Permission.catalog))
                OutlinedButton.icon(
                  onPressed: () => rules(data['rules']!),
                  icon: const Icon(Icons.tune),
                  label: const Text('Bảng phụ thu'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Tìm mã phiếu / khách / điện thoại',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Tất cả'),
                selected: status == null,
                onSelected: (_) => setState(() => status = null),
              ),
              for (var i = 0; i < 4; i++)
                ChoiceChip(
                  label: Text(tailoringStatuses[i]),
                  selected: status == i,
                  onSelected: (_) => setState(() => status = i),
                ),
            ],
          ),
          for (final row in orders)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['code']} · ${tailoringStatuses[row['status'] as int]}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${row['customer_name']} · ${row['phone']}'),
                    Text(
                      'Hẹn trả: ${(jsonDecode(row['metadata_json'] as String) as Map)['tailoring']['due_date']}',
                    ),
                    Text(
                      'Tổng ${_vnd.format(row['total'])} · Còn nợ ${_vnd.format(row['debt'])}',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              await showInvoicePdf(
                                context,
                                widget.service,
                                row['id'] as String,
                              );
                            } catch (e) {
                              message(e);
                            }
                          },
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Phiếu đo PDF'),
                        ),
                        DocumentAuditButton(
                          service: widget.service,
                          documentId: row['id'] as String,
                        ),
                        if ((row['status'] as int) < 3)
                          FilledButton.tonal(
                            onPressed: () => advance(row),
                            child: Text(
                              '→ ${tailoringStatuses[(row['status'] as int) + 1]}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Chưa có đơn may phù hợp.'),
            ),
        ],
      );
    },
  );
}
