import 'audit_archives_page.dart';

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../core/sync/cloud_api.dart';
import 'audit_page.dart' show actionLabels;

class CloudAuditPage extends StatefulWidget {
  const CloudAuditPage({
    super.key,
    required this.api,
    required this.storeId,
    this.canArchive = false,
  });
  final CloudApi api;
  final String storeId;
  final bool canArchive;
  @override
  State<CloudAuditPage> createState() => _CloudAuditPageState();
}

class _CloudAuditPageState extends State<CloudAuditPage> {
  final user = TextEditingController(),
      device = TextEditingController(),
      entity = TextEditingController();
  List<Map<String, dynamic>> stores = [], rows = [];
  late String store = widget.storeId;
  String action = '', severity = '', cursor = '', error = '';
  bool busy = false, more = false, owner = false;
  DateTime from = DateTime.now().subtract(const Duration(days: 7)),
      to = DateTime.now();
  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    user.dispose();
    device.dispose();
    entity.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      final data = await widget.api.send('/audit/options');
      if (!mounted) return;
      setState(() {
        stores = (data['stores'] as List).cast<Map<String, dynamic>>();
        owner = data['can_all_stores'] == true;
      });
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> load({bool next = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
      if (!next) {
        rows = [];
        cursor = '';
      }
    });
    try {
      final query = Uri(
        queryParameters: {
          'store': store,
          'from': day(from),
          'to': day(to),
          'user_id': user.text.trim(),
          'device_id': device.text.trim(),
          'entity_id': entity.text.trim(),
          'action': action,
          'severity': severity,
          if (next) 'cursor': cursor,
        },
      ).query;
      final data = await widget.api.send('/audit/read?$query');
      if (mounted) {
        setState(() {
          rows = (data['rows'] as List).cast<Map<String, dynamic>>();
          cursor = data['cursor'] as String;
          more = data['has_more'] == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> dates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: from, end: to),
    );
    if (picked != null && mounted) {
      setState(() {
        from = picked.start;
        to = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: store,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cửa hàng'),
                items: [
                  if (owner)
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('Toàn hệ thống'),
                    ),
                  for (final s in stores)
                    DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text('${s['code']} · ${s['name']}'),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => store = v!),
              ),
            ),
            OutlinedButton(
              onPressed: busy ? null : dates,
              child: Text('${day(from)} → ${day(to)}'),
            ),
            for (final entry in [
              (user, 'ID nhân viên'),
              (device, 'ID thiết bị'),
              (entity, 'ID chứng từ/đối tượng'),
            ])
              SizedBox(
                width: 200,
                child: TextField(
                  controller: entry.$1,
                  decoration: InputDecoration(labelText: entry.$2),
                ),
              ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: action,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Thao tác'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Tất cả thao tác'),
                  ),
                  for (final a in actionLabels.entries)
                    DropdownMenuItem(value: a.key, child: Text(a.value)),
                ],
                onChanged: busy ? null : (v) => setState(() => action = v!),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: severity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mức độ'),
                items: [
                  for (final x in [
                    ('', 'Tất cả'),
                    ('normal', 'Bình thường'),
                    ('sensitive', 'Nhạy cảm'),
                    ('critical', 'Nghiêm trọng'),
                  ])
                    DropdownMenuItem(value: x.$1, child: Text(x.$2)),
                ],
                onChanged: busy ? null : (v) => setState(() => severity = v!),
              ),
            ),
            FilledButton(
              onPressed: busy ? null : () => load(),
              child: const Text('Xem nhật ký'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Kho nhật ký cũ')),
                          body: AuditArchivesPage(
                            api: widget.api,
                            storeId: store == 'all' ? widget.storeId : store,
                            canArchive: widget.canArchive,
                          ),
                        ),
                      ),
                    ),
              child: const Text('Kho nhật ký cũ'),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'Chỉ dữ liệu đã lên cloud · Tối đa 31 ngày/lần · Xếp theo cửa hàng, thời gian và ID. Dùng Trang tiếp khi bộ lọc chưa có kết quả.',
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(error, style: const TextStyle(color: Colors.red)),
        ),
      for (final r in rows)
        ExpansionTile(
          key: ValueKey(r['id']),
          title: Text(
            '${actionLabels[r['action']] ?? r['action']} · ${r['document_code'] ?? r['entity_id']}',
          ),
          subtitle: Text(
            '${r['store_id']} · ${r['client_time']}\n${r['user_id'] ?? 'Hệ thống'} · ${r['device_id']}',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  'Lý do: ${r['reason']}\n${const JsonEncoder.withIndent('  ').convert(jsonDecode(r['changes_json'] as String))}',
                ),
              ),
            ),
          ],
        ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton(
            onPressed: more && !busy ? () => load(next: true) : null,
            child: const Text('Trang tiếp'),
          ),
        ),
      ),
    ],
  );
}
