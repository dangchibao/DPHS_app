import 'dart:convert';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../pos/sales_service.dart';
import 'transfer_service.dart';

List<Map<String, Object?>> _rows(Object? json) => json == null
    ? []
    : (jsonDecode(json as String) as List)
          .map((r) => Map<String, Object?>.from(r as Map))
          .toList();
String _date(Object? value) => value == null
    ? ''
    : DateFormat('dd/MM/yyyy HH:mm').format(
        DateTime.parse(value as String).toUtc().add(const Duration(hours: 7)),
      );
Widget _counts(Map<String, Object?> row) {
  final sent = _rows(row['items_json']),
      received = _rows(row['received_counts']);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final i in sent)
        Builder(
          builder: (_) {
            final actual =
                received
                        .where((r) => r['variant_id'] == i['variant_id'])
                        .firstOrNull?['quantity']
                    as int?;
            final delta = actual == null
                ? null
                : actual - (i['quantity'] as int);
            return Text(
              '${i['name']} · ${i['size']} · ${i['color']}: xuất ${i['quantity']} ${i['unit']}${actual == null ? '' : ' · nhận $actual · lệch ${delta! > 0 ? '+' : ''}$delta'}',
              style: TextStyle(
                color: delta != null && delta != 0 ? Colors.red : null,
              ),
            );
          },
        ),
    ],
  );
}

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key, required this.service});
  final LocalService service;
  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  List<Map<String, Object?>> outgoing = [], incoming = [];
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await Future.wait([
        widget.service.outgoingTransfers(),
        widget.service.incomingTransfers(),
      ]);
      if (mounted) {
        setState(() {
          outgoing = result[0];
          incoming = result[1];
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    }
  }

  Future<void> create() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TransferOutDialog(service: widget.service),
    );
    if (saved == true && mounted) {
      await load();
    }
  }

  Future<void> dispatch(Map<String, Object?> row) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _DispatchDialog(service: widget.service, id: row['id'] as String),
    );
    if (saved == true && mounted) {
      await load();
    }
  }

  Future<void> receive(Map<String, Object?> row) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ReceiveDialog(service: widget.service, offer: row),
    );
    if (saved == true && mounted) {
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Chuyển kho liên chi nhánh',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.add),
                label: const Text('Tạo phiếu xuất chuyển'),
              ),
              IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        const TabBar(
          tabs: [
            Tab(text: 'Phiếu xuất'),
            Tab(text: 'Hàng chờ nhận'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              ListView(
                children: [
                  for (final d in outgoing)
                    Builder(
                      builder: (_) {
                        final meta =
                            jsonDecode(d['metadata_json'] as String) as Map;
                        final state = d['receipt_code'] != null
                            ? 'Đã nhận'
                            : d['dispatched'] == 1
                            ? 'Đang chuyển'
                            : 'Đã xuất';
                        return Card(
                          margin: const EdgeInsets.all(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${d['code']} · $state',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Đến ${meta['target_store_code']} · máy ${meta['target_device_code']} · ${_date(d['issued_at'])}',
                                ),
                                _counts(d),
                                Text(meta['notes'] as String? ?? ''),
                                if (d['receipt_code'] != null)
                                  Text(
                                    'Biên nhận ${d['receipt_code']} · ${d['receiver_name']} · ${d['receipt_reason']}',
                                  ),
                                if (d['dispatched'] == 0 &&
                                    d['device_id'] == widget.service.deviceId)
                                  FilledButton(
                                    onPressed: () => dispatch(d),
                                    child: const Text('Giao vận chuyển'),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              ListView(
                children: [
                  if (incoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Chưa có hàng chuyển tới máy này. Đồng bộ sau khi cửa hàng nguồn giao vận chuyển.',
                      ),
                    ),
                  for (final o in incoming)
                    Card(
                      margin: const EdgeInsets.all(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${o['source_code']} · ${o['receipt_id'] == null ? 'Đang chuyển' : 'Đã nhận'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Từ ${o['source_store_code']} · ${_date(o['dispatched_at'])}',
                            ),
                            _counts(o),
                            Text(o['notes'] as String),
                            if (o['receipt_id'] == null)
                              FilledButton(
                                onPressed: () => receive(o),
                                child: const Text('Kiểm đếm · nhận hàng'),
                              )
                            else
                              Text(
                                'Lý do nhận/chênh lệch: ${o['receipt_reason']}',
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TransferOutDialog extends StatefulWidget {
  const _TransferOutDialog({required this.service});
  final LocalService service;
  @override
  State<_TransferOutDialog> createState() => _TransferOutDialogState();
}

class _TransferOutDialogState extends State<_TransferOutDialog> {
  final reason = TextEditingController();
  List<Map<String, Object?>> catalog = [], targets = [];
  final amounts = <String, String>{};
  String? target, error;
  String filter = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await Future.wait([
        widget.service.catalog(),
        widget.service.transferTargets(),
      ]);
      if (mounted) {
        setState(() {
          catalog = result[0];
          targets = result[1];
          target = targets.firstOrNull?['device_id'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    }
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final id = target;
      if (id == null) {
        throw StateError(
          'Chưa có máy nhận được duyệt. Kết nối và đồng bộ danh sách điểm nhận.',
        );
      }
      await widget.service.createTransferOut(
        targetDeviceId: id,
        items: [
          for (final e in amounts.entries)
            if ((int.tryParse(e.value) ?? 0) > 0)
              CartItem(e.key, int.parse(e.value)),
        ],
        reason: reason.text,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
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
  Widget build(BuildContext context) {
    final rows = catalog
        .where(
          (v) =>
              '${v['name']} ${v['size']} ${v['color']} ${v['sku']} ${v['barcode']}'
                  .toLowerCase()
                  .contains(filter.toLowerCase()),
        )
        .take(200)
        .toList();
    return AlertDialog(
      title: const Text('Tạo phiếu xuất chuyển'),
      content: SizedBox(
        width: 700,
        height: 520,
        child: Column(
          children: [
            if (targets.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: target,
                decoration: const InputDecoration(
                  labelText: 'Cửa hàng / máy nhận chỉ định',
                ),
                items: [
                  for (final t in targets)
                    DropdownMenuItem(
                      value: t['device_id'] as String,
                      child: Text(
                        '${t['store_code']} · ${t['device_code']} · ${t['device_name']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => target = v),
              )
            else
              const Text(
                'Chưa có điểm nhận khác chi nhánh. Chủ cần đăng ký/duyệt máy nhận rồi đồng bộ.',
              ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              enabled: !busy,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Lý do chuyển (bắt buộc)',
              ),
            ),
            TextField(
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Tìm hàng / mã vạch',
              ),
              onChanged: (v) => setState(() => filter = v),
            ),
            const Text(
              'Tối đa 20 biến thể. Tồn khả dụng đã trừ hàng đang giữ.',
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final v = rows[i], id = v['id'] as String;
                  return ListTile(
                    title: Text('${v['name']} · ${v['size']} · ${v['color']}'),
                    subtitle: Text('Khả dụng máy: ${v['device_available']}'),
                    trailing: SizedBox(
                      width: 86,
                      child: TextFormField(
                        key: ValueKey(id),
                        enabled: !busy,
                        initialValue: amounts[id] ?? '0',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'SL xuất',
                          counterText: '',
                        ),
                        onChanged: (v) => amounts[id] = v,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
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
          child: Text(busy ? 'Đang ghi…' : 'Xác nhận xuất kho'),
        ),
      ],
    );
  }
}

class _DispatchDialog extends StatefulWidget {
  const _DispatchDialog({required this.service, required this.id});
  final LocalService service;
  final String id;
  @override
  State<_DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends State<_DispatchDialog> {
  final reason = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.service.dispatchTransfer(widget.id, reason.text);
      if (mounted) {
        Navigator.pop(context, true);
      }
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
    title: const Text('Giao vận chuyển'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Xác nhận hàng đã giao vận chuyển. Sau đồng bộ, máy nhận chỉ định sẽ thấy phiếu để kiểm đếm.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            enabled: !busy,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Lý do / ghi chú giao',
            ),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
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
        child: const Text('Xác nhận đang chuyển'),
      ),
    ],
  );
}

class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({required this.service, required this.offer});
  final LocalService service;
  final Map<String, Object?> offer;
  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  final reason = TextEditingController();
  late final items = _rows(widget.offer['items_json']);
  late final amounts = {
    for (final i in items)
      i['variant_id'] as String: TextEditingController(
        text: '${i['quantity']}',
      ),
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    for (final c in amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final quantities = <String, int>{};
      for (final e in amounts.entries) {
        final n = int.tryParse(e.value.text);
        if (n == null) {
          throw ArgumentError('Cần nhập thực nhận từng món, kể cả 0.');
        }
        quantities[e.key] = n;
      }
      await widget.service.receiveTransfer(
        offerId: widget.offer['id'] as String,
        quantities: quantities,
        reason: reason.text,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
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
    title: const Text('Kiểm đếm · nhận hàng'),
    content: SizedBox(
      width: 650,
      height: 450,
      child: Column(
        children: [
          const Text(
            'Nhập số thực nhận cho mọi món, kể cả 0. Thiếu/dư phải giải thích rõ; số nhận chỉ được ghi một lần, không tự sửa tồn nguồn.',
          ),
          Expanded(
            child: ListView(
              children: [
                for (final i in items)
                  ListTile(
                    title: Text('${i['name']} · ${i['size']} · ${i['color']}'),
                    subtitle: Text('Đã xuất ${i['quantity']} ${i['unit']}'),
                    trailing: SizedBox(
                      width: 110,
                      child: TextField(
                        controller: amounts[i['variant_id']],
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: 'Thực nhận ${i['size']}',
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextField(
            controller: reason,
            enabled: !busy,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Lý do nhận / chênh lệch (bắt buộc)',
            ),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
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
        child: Text(busy ? 'Đang ghi…' : 'Xác nhận nhận hàng'),
      ),
    ],
  );
}
