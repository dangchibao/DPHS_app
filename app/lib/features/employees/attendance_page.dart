import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../../core/sync/sync_engine.dart';
import 'attendance_service.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key, required this.service});
  final LocalService service;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  late final month = TextEditingController(
    text: DateFormat('MM/yyyy')
        .format(widget.service.clock().toUtc().add(const Duration(hours: 7))),
  );
  List<Map<String, Object?>> entries = [], rejections = [], employees = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
    widget.service.syncEngine?.addListener(onSync);
  }

  @override
  void dispose() {
    widget.service.syncEngine?.removeListener(onSync);
    month.dispose();
    super.dispose();
  }

  void onSync() {
    final session = widget.service.session;
    if (mounted &&
        !busy &&
        session != null &&
        session.can(Permission.attendance) &&
        session.expiresAt.isAfter(widget.service.clock()) &&
        widget.service.syncEngine?.status != SyncStatus.syncing) {
      load();
    }
  }

  (String, String) range() {
    final match = RegExp(r'^(\d{2})/(\d{4})$').firstMatch(month.text.trim());
    if (match == null) {
      throw ArgumentError('Nhập tháng/năm dạng MM/YYYY.');
    }
    final m = int.parse(match[1]!), y = int.parse(match[2]!);
    if (m < 1 || m > 12 || y < 1) {
      throw ArgumentError('Tháng/năm không hợp lệ.');
    }
    return (
      DateFormat('yyyy-MM-dd').format(DateTime.utc(y, m)),
      DateFormat('yyyy-MM-dd').format(DateTime.utc(y, m + 1)),
    );
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final (from, to) = range();
      final result = await Future.wait([
        widget.service.attendance(from: from, to: to),
        widget.service.attendanceRejections(from: from, to: to),
        widget.service.attendanceEmployees(),
      ]);
      if (mounted) {
        setState(() {
          entries = result[0];
          rejections = result[1];
          employees = result[2];
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

  Future<void> mark([Map<String, Object?>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AttendanceDialog(
        service: widget.service,
        employees: employees,
        row: row,
      ),
    );
    if (saved == true && mounted) {
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Chấm công nhân viên',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
            SizedBox(
              width: 190,
              child: TextField(
                controller: month,
                decoration: const InputDecoration(
                  labelText: 'Tháng/năm (MM/YYYY)',
                ),
                onSubmitted: (_) => load(),
              ),
            ),
            OutlinedButton(
              onPressed: busy ? null : load,
              child: const Text('Xem tháng'),
            ),
            FilledButton.icon(
              onPressed: busy || employees.isEmpty ? null : () => mark(),
              icon: const Icon(Icons.add),
              label: const Text('Ghi ngày công'),
            ),
          ],
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(error!, style: const TextStyle(color: Colors.red)),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Tổng công đã ghi: ${daysText(entries.fold<int>(0, (n, r) => n + (r['day_units'] as int)))} ngày · 0 / 0,5 / 1 ngày mỗi nhân viên/ngày.',
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            if (entries.isEmpty && !busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Chưa có bản chấm công trong tháng.'),
              ),
            for (final r in entries)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text('${r['display_name']} · ${r['work_day']}'),
                  subtitle: Text(
                    '${daysText(r['day_units'] as int)} ngày · ${r['pending'] == true ? 'Chờ đồng bộ' : 'Đã gửi/nhận đồng bộ'}\n${r['reason']}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Sửa ngày công',
                    onPressed: () => mark(r),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            for (final r in rejections)
              Card(
                color: const Color(0xfffff0f0),
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Chưa áp dụng: ${r['display_name']} · ${r['work_day']}\n${r['reason']}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _AttendanceDialog extends StatefulWidget {
  const _AttendanceDialog({
    required this.service,
    required this.employees,
    this.row,
  });
  final LocalService service;
  final List<Map<String, Object?>> employees;
  final Map<String, Object?>? row;
  @override
  State<_AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<_AttendanceDialog> {
  late String? employee =
      widget.row?['employee_id'] as String? ??
      widget.employees.firstOrNull?['id'] as String?;
  late int units = widget.row?['day_units'] as int? ?? 2;
  late DateTime day = widget.row == null
      ? widget.service.clock().toUtc().add(const Duration(hours: 7))
      : DateTime.parse(widget.row!['work_day'] as String);
  final reason = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final now = widget.service.clock().toUtc().add(const Duration(hours: 7));
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(day.year, day.month, day.day),
      firstDate: DateTime(1),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (selected != null && mounted) {
      setState(() => day = selected);
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      if (employee == null) {
        throw ArgumentError('Chọn nhân viên.');
      }
      await widget.service.markAttendance(
        employeeId: employee!,
        day: DateFormat('yyyy-MM-dd').format(day),
        units: units,
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
    title: const Text('Ghi ngày công'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: employee,
              decoration: const InputDecoration(labelText: 'Nhân viên'),
              items: [
                for (final e in widget.employees)
                  DropdownMenuItem(
                    value: e['id'] as String,
                    child: Text(
                      '${e['display_name']}${e['active'] == 0 ? ' · Ngừng phân công' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy ? null : (v) => setState(() => employee = v),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy ? null : pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text('Ngày ${DateFormat('dd/MM/yyyy').format(day)}'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: units,
              decoration: const InputDecoration(labelText: 'Ngày công'),
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text('Nghỉ / không tính công (0)'),
                ),
                DropdownMenuItem(value: 1, child: Text('Nửa ngày (0,5)')),
                DropdownMenuItem(value: 2, child: Text('Đủ ngày (1)')),
              ],
              onChanged: busy ? null : (v) => setState(() => units = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              enabled: !busy,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Lý do / ghi chú (bắt buộc)',
              ),
            ),
            const Text(
              'Lần ghi mới giữ lịch sử lần trước. Kỳ lương đã khóa cần người có quyền đối soát trước khi sửa.',
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Quay lại'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Đang ghi…' : 'Lưu ngày công'),
      ),
    ],
  );
}
