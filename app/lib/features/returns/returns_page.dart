import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import 'return_pricing.dart';
import 'return_service.dart';
import 'return_pdf.dart';

final _vnd = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: '₫',
  decimalDigits: 0,
);

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({super.key, required this.service, this.initialDocumentId});
  final LocalService service;
  final String? initialDocumentId;
  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  late Future<Map<String, List<Map<String, Object?>>>> future;
  final search = TextEditingController();
  bool history = false;
  @override
  void initState() {
    super.initState();
    refresh();
    if (widget.initialDocumentId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => open(widget.initialDocumentId!),
      );
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void refresh() {
    future = load();
  }

  Future<Map<String, List<Map<String, Object?>>>> load() async => {
    'candidates': await widget.service.returnableDocuments(search: search.text),
    'history': await widget.service.returnsHistory(),
  };
  void message(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> open(String originalId, {bool voidOriginal = false}) async {
    try {
      final lines = await widget.service.returnableLines(originalId),
          products = await widget.service.catalog();
      if (!mounted) {
        return;
      }
      if (lines.every(
        (l) => (l['quantity'] as int) <= (l['returned'] as int),
      )) {
        throw StateError('Đã đổi/trả hết các món trên chứng từ.');
      }
      final done = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ReturnEditor(
          service: widget.service,
          originalId: originalId,
          lines: lines,
          products: products,
          voidOriginal: voidOriginal,
        ),
      );
      if (done == true && mounted) {
        setState(refresh);
      }
    } catch (e) {
      message(e);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Chọn hóa đơn')),
                ButtonSegment(value: true, label: Text('Phiếu đổi/trả')),
              ],
              selected: {history},
              onSelectionChanged: (v) => setState(() => history = v.single),
            ),
            if (!history)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: search,
                  onSubmitted: (_) => setState(refresh),
                  decoration: InputDecoration(
                    labelText: 'Tìm mã hóa đơn / khách',
                    suffixIcon: IconButton(
                      onPressed: () => setState(refresh),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data![history ? 'history' : 'candidates']!;
            if (rows.isEmpty) {
              return Center(
                child: Text(
                  history
                      ? 'Chưa có phiếu đổi/trả.'
                      : 'Không tìm thấy chứng từ còn hàng được đổi/trả.',
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index],
                    metadata =
                        jsonDecode(row['metadata_json'] as String) as Map;
                if (history) {
                  return Card(
                    child: ListTile(
                      title: Text(
                        '${row['code']}${metadata['void_original'] == true ? ' · Hủy hóa đơn' : ''}',
                      ),
                      subtitle: Text(
                        'Gốc: ${metadata['original_code']}\nNhận lại ${_vnd.format(metadata['returned_value'])} · Hoàn ${_vnd.format(metadata['refund'])}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Phiếu đổi/trả PDF',
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        onPressed: () async {
                          try {
                            await showReturnPdf(
                              context,
                              widget.service,
                              row['id'] as String,
                            );
                          } catch (e) {
                            message(e);
                          }
                        },
                      ),
                    ),
                  );
                }
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['code'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('${row['customer_name']} · ${row['issued_at']}'),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: () => open(row['id'] as String),
                              child: const Text('Đổi size / đổi trả'),
                            ),
                            if (row['type'] == 'HD' &&
                                widget.service.session!.can(
                                  Permission.voidInvoice,
                                ))
                              TextButton(
                                onPressed: () => open(
                                  row['id'] as String,
                                  voidOriginal: true,
                                ),
                                child: const Text('Hủy hóa đơn'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}

class _LineEditor {
  _LineEditor(this.source, {required bool all})
    : count = TextEditingController(
        text: all
            ? '${(source['quantity'] as int) - (source['returned'] as int)}'
            : '0',
      ),
      newCount = TextEditingController(text: '1');
  final Map<String, Object?> source;
  final TextEditingController count, newCount;
  String? replacement;
  bool keepPrice = true;
  int get quantity => int.tryParse(count.text) ?? 0;
  void dispose() {
    count.dispose();
    newCount.dispose();
  }
}

class _ReturnEditor extends StatefulWidget {
  const _ReturnEditor({
    required this.service,
    required this.originalId,
    required this.lines,
    required this.products,
    required this.voidOriginal,
  });
  final LocalService service;
  final String originalId;
  final List<Map<String, Object?>> lines, products;
  final bool voidOriginal;
  @override
  State<_ReturnEditor> createState() => _ReturnEditorState();
}

class _ReturnEditorState extends State<_ReturnEditor> {
  late List<_LineEditor> lines;
  late String commandId;
  final reason = TextEditingController(),
      received = TextEditingController(text: '0'),
      name = TextEditingController(),
      phone = TextEditingController();
  String method = 'cash';
  bool saving = false, pricing = false;
  String? error;
  ReturnQuote? quote;
  Timer? timer;
  int ticket = 0;
  @override
  void initState() {
    super.initState();
    commandId = widget.service.uuid.v7();
    lines = [
      for (final l in widget.lines)
        if ((l['quantity'] as int) > (l['returned'] as int))
          _LineEditor(l, all: widget.voidOriginal),
    ];
    if (widget.voidOriginal) {
      WidgetsBinding.instance.addPostFrameCallback((_) => schedule());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    ticket++;
    for (final l in lines) {
      l.dispose();
    }
    for (final c in [reason, received, name, phone]) {
      c.dispose();
    }
    super.dispose();
  }

  List<ReturnSelection> selections() => [
    for (final l in lines)
      if (l.quantity > 0) ReturnSelection(l.source['id'] as String, l.quantity),
  ];
  List<ReplacementSelection> replacements() => [
    for (final l in lines)
      if (l.quantity > 0 && l.replacement != null)
        ReplacementSelection(
          l.replacement!,
          int.tryParse(l.newCount.text) ?? 0,
          sourceLineId: l.keepPrice ? l.source['id'] as String : null,
        ),
  ];
  void schedule() {
    if (!mounted || saving) {
      return;
    }
    timer?.cancel();
    final current = ++ticket;
    setState(() {
      pricing = true;
      quote = null;
      error = null;
    });
    timer = Timer(const Duration(milliseconds: 150), () => price(current));
  }

  Future<void> price(int current) async {
    if (!mounted || current != ticket) {
      return;
    }
    final items = selections();
    if (items.isEmpty) {
      setState(() => pricing = false);
      return;
    }
    try {
      var result = await widget.service.quoteReturn(
        originalId: widget.originalId,
        items: items,
        replacements: replacements(),
        voidOriginal: widget.voidOriginal,
      );
      if (!mounted || current != ticket) {
        return;
      }
      if (result.settlement.cashDue < 0) {
        received.text = '0';
      }
      final paid = int.tryParse(received.text) ?? 0;
      if (paid > 0) {
        result = await widget.service.quoteReturn(
          originalId: widget.originalId,
          items: items,
          replacements: replacements(),
          received: paid,
          voidOriginal: widget.voidOriginal,
        );
      }
      if (mounted && current == ticket) {
        setState(() {
          quote = result;
          pricing = false;
        });
      }
    } catch (e) {
      if (mounted && current == ticket) {
        setState(() {
          error = e.toString().replaceFirst('Bad state: ', '');
          pricing = false;
        });
      }
    }
  }

  Future<void> save() async {
    final q = quote;
    if (q == null || saving || pricing) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    timer?.cancel();
    ticket++;
    try {
      await widget.service.createReturn(
        originalId: widget.originalId,
        items: selections(),
        replacements: replacements(),
        reason: reason.text,
        received: q.settlement.received,
        method: method,
        customerName: name.text,
        phone: phone.text,
        voidOriginal: widget.voidOriginal,
        commandId: commandId,
        expectedCashDue: q.settlement.cashDue,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.voidOriginal ? 'Hủy hóa đơn bằng phiếu mới' : 'Đổi size / đổi trả',
    ),
    content: SizedBox(
      width: 700,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.voidOriginal)
              const Text(
                'Nhận lại toàn bộ số món còn lại; hóa đơn gốc được giữ nguyên.',
              ),
            for (final l in lines)
              Card(
                child: ExpansionTile(
                  initiallyExpanded: lines.length <= 3,
                  title: Text(
                    '${l.source['name']} · ${l.source['size']} · ${l.source['color']}',
                  ),
                  subtitle: Text(
                    'Còn được trả: ${(l.source['quantity'] as int) - (l.source['returned'] as int)} ${l.source['unit']}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TextField(
                            controller: l.count,
                            enabled: !saving && !widget.voidOriginal,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Số lượng nhận lại',
                            ),
                            onChanged: (_) {
                              if (l.replacement != null) {
                                l.newCount.text = l.count.text;
                              }
                              schedule();
                            },
                          ),
                          if (!widget.voidOriginal) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: '',
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Hàng thay thế',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('Không đổi hàng khác'),
                                ),
                                for (final p in widget.products)
                                  DropdownMenuItem(
                                    value: p['id'] as String,
                                    child: Text(
                                      '${p['name']} · ${p['size']} · ${p['color']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: saving
                                  ? null
                                  : (value) {
                                      l.replacement = value!.isEmpty
                                          ? null
                                          : value;
                                      if (l.replacement != null) {
                                        final p = widget.products.firstWhere(
                                          (p) => p['id'] == l.replacement,
                                        );
                                        l.keepPrice =
                                            p['product_id'] ==
                                            l.source['product_id'];
                                        l.newCount.text =
                                            '${l.quantity > 0 ? l.quantity : 1}';
                                      }
                                      schedule();
                                    },
                            ),
                            if (l.replacement != null) ...[
                              TextField(
                                controller: l.newCount,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Số lượng thay thế',
                                ),
                                onChanged: (_) => schedule(),
                              ),
                              if (widget.products.firstWhere(
                                    (p) => p['id'] == l.replacement,
                                  )['product_id'] ==
                                  l.source['product_id'])
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Đổi size: giữ giá sau ưu đãi của món nhận lại',
                                  ),
                                  value: l.keepPrice,
                                  onChanged: saving
                                      ? null
                                      : (v) {
                                          l.keepPrice = v!;
                                          schedule();
                                        },
                                ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: reason,
              enabled: !saving,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Lý do đổi/trả (bắt buộc)',
              ),
            ),
            if (pricing) const LinearProgressIndicator(),
            if (quote != null) ...[
              Text('Giá trị nhận lại: ${_vnd.format(quote!.returnedValue)}'),
              Text('Hàng thay thế: ${_vnd.format(quote!.replacementValue)}'),
              Text(
                'Cấn nợ chứng từ gốc: ${_vnd.format(quote!.settlement.offset)}',
              ),
              Text(
                quote!.settlement.refund > 0
                    ? 'Hoàn lại: ${_vnd.format(quote!.settlement.refund)}'
                    : 'Chênh lệch cần thu: ${_vnd.format(quote!.settlement.cashDue)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (quote!.settlement.refund == 0)
                Text(
                  'Công nợ mới nếu chưa thu đủ: ${_vnd.format(quote!.settlement.newDebt)}',
                ),
            ],
            TextField(
              controller: received,
              enabled:
                  !saving && (quote == null || quote!.settlement.refund == 0),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Tiền nhận thêm (VND, có thể đặt cọc)',
              ),
              onChanged: (_) => schedule(),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Tiền mặt')),
                ButtonSegment(value: 'bank', label: Text('Chuyển khoản')),
              ],
              selected: {method},
              onSelectionChanged: saving
                  ? null
                  : (v) => setState(() => method = v.single),
            ),
            if (quote?.original['customer_id'] == null) ...[
              TextField(
                controller: name,
                enabled: !saving,
                decoration: const InputDecoration(
                  labelText: 'Tên khách (bắt buộc nếu còn nợ mới)',
                ),
              ),
              TextField(
                controller: phone,
                enabled: !saving,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Điện thoại'),
              ),
            ],
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            TextButton.icon(
              onPressed: saving ? null : schedule,
              icon: const Icon(Icons.refresh),
              label: const Text('Tính lại chênh lệch'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Đóng'),
      ),
      FilledButton(
        onPressed: saving || pricing || quote == null ? null : save,
        child: Text(
          saving
              ? 'Đang ghi nhận…'
              : widget.voidOriginal
              ? 'Hủy hóa đơn & tạo phiếu'
              : 'Xác nhận đổi/trả',
        ),
      ),
    ],
  );
}
