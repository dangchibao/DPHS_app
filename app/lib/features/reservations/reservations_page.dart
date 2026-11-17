import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../pos/pos_page.dart';
import '../pos/sales_service.dart';
import 'reservation_service.dart';

class ReservationsPage extends StatefulWidget {
  const ReservationsPage({super.key, required this.service});
  final LocalService service;
  @override
  State<ReservationsPage> createState() => _ReservationsPageState();
}

class _ReservationsPageState extends State<ReservationsPage> {
  List<Map<String, Object?>> rows = [];
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
      final data = await widget.service.reservations();
      if (mounted) setState(() => rows = data);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> create() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ReservationEditor(service: widget.service),
    );
    if (saved == true) await load();
  }

  Future<void> release(String id) async {
    final reason = TextEditingController();
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Giải phóng hàng giữ'),
        content: TextField(
          controller: reason,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Lý do bắt buộc'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Giải phóng'),
          ),
        ],
      ),
    );
    final accepted = await Navigator.of(context).push(route);
    await route.completed;
    if (accepted == true) {
      try {
        await widget.service.releaseReservation(id, reason.text);
        await load();
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            const Text('Giữ hàng có hạn · chưa thu tiền, chưa xuất kho'),
            if (widget.service.session!.can(Permission.sell))
              FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.add),
                label: const Text('Tạo phiếu giữ hàng'),
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
      Expanded(
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i],
                meta = jsonDecode(row['metadata_json'] as String) as Map;
            final own = row['device_id'] == widget.service.deviceId;
            final active =
                row['resolution'] == null &&
                DateTime.parse(meta['expires_at'] as String)
                    .isAfter(widget.service.clock());
            final state = row['resolution'] == 'consume'
                ? 'Đã giao'
                : row['resolution'] == 'release'
                ? 'Đã giải phóng'
                : active
                ? 'Đang giữ'
                : 'Hết hạn';
            final expiry = DateTime.parse(meta['expires_at'] as String)
                .toUtc()
                .add(const Duration(hours: 7))
                .toString()
                .substring(0, 16);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['code']} · $state',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${meta['customer_name']} · ${meta['phone']}\nHạn giữ: $expiry (giờ Việt Nam)${own ? '' : ' · Thiết bị khác'}',
                    ),
                    if (active && own)
                      Wrap(
                        spacing: 12,
                        children: [
                          if (widget.service.session!.can(Permission.sell))
                            FilledButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                        title: Text('Giao ${row['code']}'),
                                      ),
                                      body: PosPage(
                                        service: widget.service,
                                        initialReservationId:
                                            row['id'] as String,
                                      ),
                                    ),
                                  ),
                                );
                                await load();
                              },
                              child: const Text('Giao hàng · thanh toán'),
                            ),
                          TextButton(
                            onPressed: () => release(row['id'] as String),
                            child: const Text('Giải phóng'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _ReservationEditor extends StatefulWidget {
  const _ReservationEditor({required this.service});
  final LocalService service;
  @override
  State<_ReservationEditor> createState() => _ReservationEditorState();
}

class _ReservationEditorState extends State<_ReservationEditor> {
  final name = TextEditingController(),
      phone = TextEditingController(),
      hours = TextEditingController(text: '24');
  List<Map<String, Object?>> catalog = [];
  final quantities = <String, int>{};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.service.catalog();
      if (mounted) setState(() => catalog = data);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    hours.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final n = int.tryParse(hours.text);
      if (n == null || n < 1 || n > 720) {
        throw ArgumentError('Thời hạn từ 1 đến 720 giờ.');
      }
      await widget.service.reserveItems(
        [
          for (final e in quantities.entries)
            if (e.value > 0) CartItem(e.key, e.value),
        ],
        name: name.text,
        phone: phone.text,
        duration: Duration(hours: n),
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
    title: const Text('Tạo phiếu giữ hàng'),
    content: SizedBox(
      width: 600,
      height: 480,
      child: Column(
        children: [
          TextField(
            controller: name,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Tên phụ huynh'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: phone,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Điện thoại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: hours,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Thời hạn (giờ)',
                  ),
                ),
              ),
            ],
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          Expanded(
            child: ListView(
              children: [
                for (final v in catalog)
                  ListTile(
                    title: Text('${v['name']} · ${v['size']} · ${v['color']}'),
                    subtitle: Text('Khả dụng máy: ${v['device_available']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: busy
                              ? null
                              : () => setState(
                                  () => quantities[v['id'] as String] =
                                      ((quantities[v['id']] ?? 0) - 1).clamp(
                                        0,
                                        100000,
                                      ),
                                ),
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${quantities[v['id']] ?? 0}'),
                        IconButton(
                          onPressed: busy
                              ? null
                              : () => setState(
                                  () => quantities[v['id'] as String] =
                                      (quantities[v['id']] ?? 0) + 1,
                                ),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
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
        child: Text(busy ? 'Đang lưu…' : 'Giữ hàng'),
      ),
    ],
  );
}
