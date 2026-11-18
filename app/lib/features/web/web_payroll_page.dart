import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../core/sync/cloud_api.dart';
import '../../core/money.dart';

class WebPayrollPage extends StatefulWidget {
  const WebPayrollPage({super.key, required this.api});
  final CloudApi api;
  @override
  State<WebPayrollPage> createState() => _WebPayrollPageState();
}

class _WebPayrollPageState extends State<WebPayrollPage> {
  final month = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 7),
  );
  List<Map<String, dynamic>> employees = [], rows = [];
  Map<String, Object?>? quote;
  String? employee, error;
  String rosterCursor = '', historyCursor = '';
  bool busy = false, moreEmployees = false, moreHistory = false;
  @override
  void initState() {
    super.initState();
    roster();
  }

  @override
  void dispose() {
    month.dispose();
    super.dispose();
  }

  Future<void> roster({bool next = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await widget.api.send(
        '/web/payroll${next ? '?cursor=${Uri.encodeComponent(rosterCursor)}' : ''}',
      );
      if (mounted) {
        setState(() {
          employees = (data['employees'] as List).cast<Map<String, dynamic>>();
          rosterCursor = data['cursor'] as String;
          moreEmployees = data['has_more'] == true;
          employee = employees.firstOrNull?['id'] as String?;
          rows = [];
          quote = null;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load({bool preview = false, bool next = false}) async {
    if (busy || employee == null) return;
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month.text.trim())) {
      setState(() => error = 'Kỳ lương dạng YYYY-MM.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      quote = null;
      if (!next) rows = [];
    });
    try {
      final query = Uri(
        queryParameters: {
          'employee_id': employee!,
          'month': month.text.trim(),
          if (next) 'cursor': historyCursor,
        },
      ).query;
      final data = await widget.api.send(
        '${preview ? '/payroll/preview' : '/web/payroll'}?$query',
      );
      if (mounted) {
        setState(() {
          if (preview) {
            quote = data;
          } else {
            rows = (data['rows'] as List).cast<Map<String, dynamic>>();
            historyCursor = data['cursor'] as String;
            moreHistory = data['has_more'] == true;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String money(Object? value) =>
      '${formatWholeVnd(BigInt.parse(value.toString()))} đ';
  Widget totals(Map totals) => Wrap(
    spacing: 16,
    runSpacing: 8,
    children: [
      for (final entry in [
        ('base_pay', 'Lương theo công'),
        ('commission_pay', 'Hoa hồng'),
        ('bonus_pay', 'Thưởng'),
        ('total_pay', 'Tổng lương'),
      ])
        Text('${entry.$2}: ${money(totals[entry.$1] ?? 0)}'),
    ],
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const Text(
        'Lương online · Chỉ chủ/kế toán · Dữ liệu đã lên cloud. Cấu hình, chốt/hủy và in phiếu thực hiện tại ứng dụng Windows/Android sau đối soát các máy.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              key: ValueKey(rosterCursor),
              initialValue: employee,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Nhân viên'),
              items: [
                for (final e in employees)
                  DropdownMenuItem(
                    value: e['id'] as String,
                    child: Text(
                      '${e['display_name']}${e['active'] == 0 ? ' · Ngừng làm' : ''}',
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      employee = v;
                      rows = [];
                      quote = null;
                      moreHistory = false;
                    }),
            ),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: month,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Kỳ YYYY-MM'),
            ),
          ),
          FilledButton(
            onPressed: busy ? null : () => load(),
            child: const Text('Xem kỳ lương'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => load(preview: true),
            child: const Text('Dự tính hiện tại'),
          ),
          if (moreEmployees)
            OutlinedButton(
              onPressed: busy ? null : () => roster(next: true),
              child: const Text('Nhóm nhân viên tiếp'),
            ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      if (quote != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DỰ TÍNH · Chưa phải phiếu lương'),
                Text(
                  '${quote!['employee_name']} · ${quote!['period_start']} → ${quote!['period_end']}',
                ),
                totals(quote!['totals'] as Map),
                const Text(
                  'Chỉ gồm dữ liệu đã đồng bộ. Cần hoàn tất kỳ và đối soát mọi máy trước khi chốt.',
                ),
              ],
            ),
          ),
        ),
      for (final r in rows)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['employee_name']} · ${r['period_start']}'),
                Text(
                  r['void_reason'] != null
                      ? 'Đã hủy: ${r['void_reason']}'
                      : r['needs_reconcile'] == 1
                      ? 'Cần đối soát lại'
                      : 'Đã chốt',
                ),
                totals(jsonDecode(r['totals_json'] as String) as Map),
                Text('Chốt lúc ${r['created_at']}'),
              ],
            ),
          ),
        ),
      if (moreHistory)
        OutlinedButton(
          onPressed: busy ? null : () => load(next: true),
          child: const Text('Lịch sử tiếp'),
        ),
    ],
  );
}
