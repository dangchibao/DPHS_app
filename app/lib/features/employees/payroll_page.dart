import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/local_service.dart';
import '../../core/money.dart';
import '../../core/auth/permissions.dart';
import '../../core/sync/sync_engine.dart';
import 'payroll_service.dart';
import 'payroll_calculation.dart';
import 'payroll_pdf.dart';

int commissionBasisPoints(String value) {
  final match = RegExp(r'^(\d{1,3})(?:[,.](\d{1,2}))?$')
      .firstMatch(value.trim());
  if (match == null) {
    throw ArgumentError(
      'Hoa hồng từ 0 đến 100%, tối đa 2 chữ số sau dấu phẩy.',
    );
  }
  final result =
      int.parse(match[1]!) * 100 + int.parse((match[2] ?? '').padRight(2, '0'));
  if (result > 10000) throw ArgumentError('Hoa hồng tối đa 100%.');
  return result;
}

final _money = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: 'đ',
  decimalDigits: 0,
);

class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key, required this.service});
  final LocalService service;
  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  late final month = TextEditingController(
    text: widget.service
        .clock()
        .toUtc()
        .add(const Duration(hours: 7))
        .toIso8601String()
        .substring(0, 7),
  );
  List<Map<String, Object?>> employees = [],
      versions = [],
      history = [],
      commands = [];
  List<Map<String, Object?>> periodRows = [];
  String tableMonth = '';
  Map<String, Object?>? quote;
  String? employee, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load(userAction: true);
    widget.service.syncEngine?.addListener(onSync);
  }

  @override
  void dispose() {
    widget.service.syncEngine?.removeListener(onSync);
    month.dispose();
    super.dispose();
  }

  void onSync() {
    if (mounted &&
        !busy &&
        widget.service.session?.can(Permission.payroll) == true &&
        widget.service.syncEngine?.status != SyncStatus.syncing) {
      load();
    }
  }

  Future<void> load({bool userAction = false}) async {
    setState(() => busy = true);
    try {
      if (userAction) {
        await widget.service.recordPayrollView(employee: employee);
      }
      final roster = await widget.service.payrollEmployees();
      employee ??= roster.firstOrNull?['id'] as String?;
      final rows = await Future.wait([
        if (employee != null)
          widget.service.compensationVersions(employee!)
        else
          Future.value(<Map<String, Object?>>[]),
        if (employee != null)
          widget.service.payrollHistory(employee!)
        else
          Future.value(<Map<String, Object?>>[]),
        widget.service.payrollCommands(),
        widget.service.payrollPeriodTable(month.text.trim()),
      ]);
      if (mounted) {
        setState(() {
          employees = roster;
          versions = rows[0];
          history = rows[1];
          commands = rows[2];
          periodRows = rows[3];
          tableMonth = month.text.trim();
          quote = null;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<bool> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) {
        setState(() => error = null);
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> editRule() async {
    try {
      payrollPeriod(month.text.trim());
      final target = month.text.trim();
      final applicable = versions
          .where((v) => (v['effective_month'] as String).compareTo(target) <= 0)
          .firstOrNull;
      final existing = versions
          .where((v) => v['effective_month'] == target)
          .firstOrNull;
      final rule = await showDialog<CompensationRule>(
        context: context,
        builder: (_) => _RuleDialog(
          initial: applicable == null
              ? null
              : CompensationRule.fromJson(
                  jsonDecode(applicable['config_json'] as String),
                ),
        ),
      );
      if (rule == null || !mounted) return;
      final success = await run(() async {
        await widget.service.saveCompensation(
          employee: employee!,
          month: target,
          rule: rule,
          previousId: existing?['id'] as String?,
        );
      });
      if (success) await load();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    }
  }

  Future<bool> preview() => run(() async {
    final value = await widget.service.previewPayroll(
      employee!,
      month.text.trim(),
    );
    final table = await widget.service.payrollPeriodTable(month.text.trim());
    if (mounted) {
      setState(() {
        quote = value;
        periodRows = table;
        tableMonth = month.text.trim();
      });
    }
  });
  Future<void> issue() async {
    final snapshot = quote!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chốt phiếu lương'),
        content: const Text(
          'Xác nhận đã đối soát đầy đủ các máy, kể cả máy đã thu hồi. Phiếu đã chốt không sửa; sửa sai phải hủy và phát hành phiếu mới. Đây là phát hành phiếu lương, không chuyển tiền ngân hàng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đã đối soát · chốt phiếu'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final success = await run(() async {
      await widget.service.issuePayroll(snapshot, confirmed: true);
    });
    if (success) await load();
  }

  Future<void> voidRun(String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hủy phiếu lương'),
        content: TextField(
          controller: controller,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Lý do hủy'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Gửi yêu cầu hủy'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    final success = await run(() async {
      await widget.service.voidPayroll(id, reason);
    });
    if (success) await load();
  }

  @override
  Widget build(BuildContext context) {
    final totals = quote?['totals'] as Map?;
    final devices = quote?['devices'] as List? ?? [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Lương cơ bản · hoa hồng · thưởng',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Chỉ chủ/kế toán được xem. Có thể lập cấu hình offline; dự tính/chốt đối soát dữ liệu cloud. Chốt chỉ sau khi kết thúc tháng và các máy đã đồng bộ.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: employee,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Nhân viên'),
          items: [
            for (final e in employees)
              DropdownMenuItem(
                value: e['id'] as String,
                child: Text(
                  e['display_name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy
              ? null
              : (value) {
                  employee = value;
                  load(userAction: true);
                },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: month,
          decoration: const InputDecoration(labelText: 'Kỳ lương YYYY-MM'),
          enabled: !busy,
          onChanged: (_) => setState(() => quote = null),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: busy || employee == null ? null : editRule,
              child: const Text('Cấu hình lương'),
            ),
            FilledButton(
              onPressed: busy || employee == null ? null : preview,
              child: const Text('Đối soát · xem dự tính'),
            ),
            TextButton(
              onPressed: busy ? null : () => load(userAction: true),
              child: const Text('Tải dữ liệu máy'),
            ),
          ],
        ),
        if (totals != null) ...[
          const Divider(height: 32),
          Text(
            'Dự tính kỳ ${month.text}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            'Công: ${(totals['attendance_units'] as int) / 2} ngày; doanh số thuần: ${_money.format(totals['net_sales'])}',
          ),
          Text('Lương theo công: ${_money.format(totals['base_pay'])}'),
          Text('Hoa hồng: ${_money.format(totals['commission_pay'])}'),
          Text('Thưởng: ${_money.format(totals['bonus_pay'])}'),
          Text(
            'Tổng lương: ${_money.format(totals['total_pay'])}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (quote!['period_complete'] != true)
            const Text('Tháng chưa kết thúc; chưa thể chốt.'),
          for (final d in devices)
            Text(
              '${(d as Map)['code']} · ${d['name']}: ${d['checkpoint'] ?? 'Chưa gửi hết dữ liệu sau kỳ'}',
            ),
          if (quote!['active_run'] != null)
            const Text('Kỳ đã có phiếu đang hiệu lực.'),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed:
                  busy ||
                      quote!['period_complete'] != true ||
                      quote!['active_run'] != null ||
                      devices.any((d) => (d as Map)['checkpoint'] == null)
                  ? null
                  : issue,
              child: const Text('Chốt phiếu lương'),
            ),
          ),
        ],
        const Divider(height: 32),
        const Text(
          'Phiếu lương của nhân viên',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (history.isEmpty) const Text('Chưa có phiếu lương.'),
        for (final row in history)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(row['period_start'] as String).substring(0, 7)} · ${_money.format((jsonDecode(row['totals_json'] as String) as Map)['total_pay'])}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SelectableText('Mã: ${row['id']}'),
                  Text(
                    row['void_at'] != null
                        ? 'Đã hủy · ${row['void_reason']}'
                        : row['needs_reconcile'] == 1
                        ? 'Cần đối soát: có giao dịch bổ sung ảnh hưởng kỳ đã chốt.'
                        : 'Đã chốt · chưa ghi nhận chi trả ngân hàng',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                final bytes = await payrollPdf(
                                  widget.service,
                                  row['id'] as String,
                                );
                                await Printing.layoutPdf(
                                  onLayout: (_) async => bytes,
                                  name: 'Phieu-luong-${row['id']}.pdf',
                                );
                              }),
                        child: const Text('Xem / xuất PDF'),
                      ),
                      if (row['void_at'] == null)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => voidRun(row['id'] as String),
                          child: const Text('Hủy để đối soát lại'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 32),
        Text(
          'Bảng lương cửa hàng · $tableMonth',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Các phiếu đã nhận về máy. Phiếu hủy không tính vào tổng đang hiệu lực.',
        ),
        Text(
          'Tổng đang hiệu lực: ${formatWholeVnd(periodRows.where((p) => p['void_reason'] == null).fold<BigInt>(BigInt.zero, (sum, p) => sum + BigInt.from((jsonDecode(p['totals_json'] as String) as Map)['total_pay'] as int)))}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (periodRows.isEmpty)
          const Text('Chưa nhận được phiếu lương trong kỳ.'),
        if (periodRows.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Nhân viên')),
                DataColumn(label: Text('Tổng lương'), numeric: true),
                DataColumn(label: Text('Trạng thái')),
              ],
              rows: [
                for (final p in periodRows)
                  DataRow(
                    cells: [
                      DataCell(Text(p['employee_name'] as String)),
                      DataCell(
                        Text(
                          _money.format(
                            (jsonDecode(p['totals_json'] as String)
                                as Map)['total_pay'],
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          p['void_reason'] != null
                              ? 'Đã hủy'
                              : p['needs_reconcile'] == 1
                              ? 'Cần đối soát'
                              : 'Đang hiệu lực',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const Divider(height: 32),
        const Text(
          'Yêu cầu gần đây',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        for (final c in commands)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${{'rule': 'Cấu hình', 'issue': 'Chốt phiếu', 'void': 'Hủy phiếu'}[c['kind']]} · ${c['status'] == 'accepted'
                  ? 'Đã xác nhận'
                  : c['status'] == 'rejected'
                  ? 'Không áp dụng'
                  : c['queued'] == 1
                  ? 'Chờ gửi'
                  : 'Chờ nhận kết quả'}',
            ),
            subtitle: Text(
              c['message'] as String? ?? c['created_at'] as String,
            ),
          ),
      ],
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({this.initial});
  final CompensationRule? initial;
  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final base = TextEditingController(
        text: widget.initial?.baseSalary.toString() ?? '',
      ),
      days = TextEditingController(
        text: widget.initial?.standardDays.toString() ?? '26',
      ),
      commission = TextEditingController(
        text: widget.initial == null
            ? '0'
            : '${widget.initial!.commissionBps ~/ 100},${(widget.initial!.commissionBps % 100).toString().padLeft(2, '0')}',
      );
  late final tiers =
      <({TextEditingController threshold, TextEditingController amount})>[
        for (final t
            in widget.initial?.bonusTiers ?? <({int threshold, int amount})>[])
          (
            threshold: TextEditingController(text: '${t.threshold}'),
            amount: TextEditingController(text: '${t.amount}'),
          ),
      ];
  String? error;
  @override
  void dispose() {
    base.dispose();
    days.dispose();
    commission.dispose();
    for (final t in tiers) {
      t.threshold.dispose();
      t.amount.dispose();
    }
    super.dispose();
  }

  int number(TextEditingController c) {
    if (!RegExp(r'^\d+$').hasMatch(c.text.trim())) {
      throw ArgumentError('Nhập số nguyên không âm, không dùng dấu phân cách.');
    }
    return int.parse(c.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cấu hình lương theo kỳ'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Thưởng chỉ lấy bậc cao nhất đạt ngưỡng, không cộng dồn. Nhập 0 nếu không có khoản lương/hoa hồng.',
            ),
            TextField(
              controller: base,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Lương cơ bản VND'),
            ),
            TextField(
              controller: days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Ngày công chuẩn (1–31)',
              ),
            ),
            TextField(
              controller: commission,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Hoa hồng (%)',
                helperText: 'Ví dụ 1,5 = 1,5% doanh số thuần',
              ),
            ),
            for (final t in tiers)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: t.threshold,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Doanh số từ VND',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: t.amount,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Thưởng VND',
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() => tiers.remove(t));
                        t.threshold.dispose();
                        t.amount.dispose();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            if (tiers.length < 20)
              TextButton(
                onPressed: () => setState(
                  () => tiers.add((
                    threshold: TextEditingController(),
                    amount: TextEditingController(),
                  )),
                ),
                child: const Text('Thêm bậc thưởng'),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
          try {
            final rule = CompensationRule.fromJson({
              'base_salary': number(base),
              'standard_days': number(days),
              'commission_bps': commissionBasisPoints(commission.text),
              'bonus_tiers': [
                for (final t in tiers)
                  {
                    'threshold': number(t.threshold),
                    'amount': number(t.amount),
                  },
              ],
            });
            Navigator.pop(context, rule);
          } catch (e) {
            setState(() => error = e.toString());
          }
        },
        child: const Text('Lưu yêu cầu cấu hình'),
      ),
    ],
  );
}
