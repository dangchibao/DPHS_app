import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../../core/backup/picked_backup.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.service, required this.onReload});
  final LocalService service;
  final VoidCallback onReload;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final folder = TextEditingController(),
      password = TextEditingController(),
      hour = TextEditingController(text: '21'),
      minute = TextEditingController(text: '30'),
      days = TextEditingController(text: '7'),
      weeks = TextEditingController(text: '4'),
      months = TextEditingController(text: '12');
  bool encrypted = false, busy = false;
  String? error;
  List<Map<String, Object?>> records = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [folder, password, hour, minute, days, weeks, months]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      widget.service.require(Permission.backup);
      final settings = await widget.service.db.rows(
        "SELECT key,value FROM local_settings WHERE key LIKE 'backup_%'",
      );
      final values = {for (final row in settings) row['key']: row['value']};
      final secret = await const FlutterSecureStorage().read(
        key: 'backup_password',
      );
      final rows = await widget.service.db.rows(
        'SELECT * FROM backup_runs WHERE store_id=? AND device_id=? ORDER BY created_at DESC LIMIT 50',
        [widget.service.storeId, widget.service.deviceId],
      );
      if (mounted) {
        setState(() {
          folder.text = values['backup_folder'] as String? ?? '';
          password.text = secret ?? '';
          encrypted = secret?.isNotEmpty ?? false;
          hour.text = values['backup_hour'] as String? ?? '21';
          minute.text = values['backup_minute'] as String? ?? '30';
          days.text = values['backup_days'] as String? ?? '7';
          weeks.text = values['backup_weeks'] as String? ?? '4';
          months.text = values['backup_months'] as String? ?? '12';
          records = rows;
          error = values['backup_error'] as String?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    widget.service.require(Permission.backup);
    final h = int.parse(hour.text),
        m = int.parse(minute.text),
        d = int.parse(days.text),
        w = int.parse(weeks.text),
        mo = int.parse(months.text);
    if (h < 0 || h > 23 || m < 0 || m > 59 || d < 1 || w < 1 || mo < 1) {
      throw ArgumentError('Kiểm tra giờ, phút và số bản giữ lại.');
    }
    if (encrypted && password.text.length < 10) {
      throw ArgumentError('Mật khẩu backup tối thiểu 10 ký tự.');
    }
    const storage = FlutterSecureStorage();
    if (encrypted) {
      await storage.write(key: 'backup_password', value: password.text);
    } else {
      await storage.delete(key: 'backup_password');
    }
    await widget.service.db.transaction(() async {
      for (final e in {
        'backup_folder': folder.text.trim(),
        'backup_hour': '$h',
        'backup_minute': '$m',
        'backup_days': '$d',
        'backup_weeks': '$w',
        'backup_months': '$mo',
      }.entries) {
        if (e.value.isEmpty) {
          await widget.service.db.execute(
            'DELETE FROM local_settings WHERE key=?',
            [e.key],
          );
        } else {
          await widget.service.db.execute(
            'INSERT INTO local_settings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
            [e.key, e.value],
          );
        }
      }
      await widget.service.audit(
        'CONFIG_UPDATE',
        'backup',
        'schedule',
        reason: 'Cập nhật lịch và chính sách sao lưu',
        severity: 'sensitive',
        changes: {
          'hour': h,
          'minute': m,
          'days': d,
          'weeks': w,
          'months': mo,
          'encrypted': encrypted,
        },
      );
    });
    message('Đã lưu cấu hình sao lưu.');
  }

  Future<void> create() async {
    await save();
    final path = await widget.service.backup!.create(
      folder: folder.text.trim().isEmpty ? null : folder.text.trim(),
      password: encrypted ? password.text : null,
    );
    await widget.service.backup!.rotate(
      folder.text.trim().isEmpty
          ? path.substring(0, path.lastIndexOf(RegExp(r'[/\\]')))
          : folder.text.trim(),
      days: int.parse(days.text),
      weeks: int.parse(weeks.text),
      months: int.parse(months.text),
    );
    await load();
    message('Đã sao lưu và kiểm tra dữ liệu.');
  }

  Future<void> restore() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Chọn bản sao lưu',
      type: FileType.custom,
      allowedExtensions: ['zip', 'ntbackup'],
    );
    if (picked == null || !mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Phục hồi bản sao lưu?'),
        content: Text(
          'Tệp: ${picked.name}\n\nỨng dụng sẽ sao lưu hiện trạng và giữ các giao dịch chưa đồng bộ. Sau phục hồi cần kết nối cloud trước khi bán hàng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    final code = TextEditingController(),
        reason = TextEditingController(),
        key = TextEditingController(text: encrypted ? password.text : '');
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Xác nhận lần 2'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  decoration: const InputDecoration(
                    labelText: 'Nhập mã cửa hàng để xác nhận',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu bản sao lưu (nếu mã hóa)',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Lý do khôi phục (bắt buộc)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Khôi phục dữ liệu'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        try {
          await withBackupFile(
            picked,
            (path) => widget.service.backup!.restore(
              path,
              password: key.text.isEmpty ? null : key.text,
              confirmation: code.text,
              confirmed: true,
              reason: reason.text,
            ),
          );
          message('Đã khôi phục. Vui lòng đăng nhập để đối soát cloud.');
        } finally {
          if (widget.service.db.isClosed) widget.onReload();
        }
      }
    } finally {
      code.dispose();
      key.dispose();
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = records.where((r) => r['status'] == 'success').firstOrNull;
    final stale =
        last == null ||
        widget.service.clock().difference(
              DateTime.parse(last['created_at'] as String),
            ) >
            const Duration(days: 2);
    return AbsorbPointer(
      absorbing: busy,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Sao lưu & khôi phục',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          Card(
            color: stale ? const Color(0xfffff4df) : Colors.white,
            elevation: 0,
            child: ListTile(
              leading: Icon(
                stale ? Icons.warning_amber : Icons.verified_outlined,
              ),
              title: Text(
                stale
                    ? 'Chưa có bản sao lưu thành công trong 2 ngày gần đây'
                    : 'Dữ liệu đã được sao lưu',
              ),
              subtitle: Text(
                last == null
                    ? 'Tạo bản sao lưu đầu tiên ngay bên dưới.'
                    : 'Gần nhất: ${last['created_at']} · ${((last['bytes'] as int) / 1024 / 1024).toStringAsFixed(2)} MB',
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: folder,
            decoration: InputDecoration(
              labelText: 'Thư mục sao lưu (để trống: thư mục ứng dụng)',
              suffixIcon: IconButton(
                onPressed: () async {
                  final selected = await FilePicker.getDirectoryPath(
                    dialogTitle: 'Chọn thư mục sao lưu',
                  );
                  if (selected != null) folder.text = selected;
                },
                icon: const Icon(Icons.folder_open),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final item in [
                (hour, 'Giờ'),
                (minute, 'Phút'),
                (days, 'Bản ngày'),
                (weeks, 'Bản tuần'),
                (months, 'Bản tháng'),
              ])
                SizedBox(
                  width: 115,
                  child: TextField(
                    controller: item.$1,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: item.$2),
                  ),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mã hóa bản sao lưu bằng mật khẩu'),
            value: encrypted,
            onChanged: (value) => setState(() => encrypted = value),
          ),
          if (encrypted)
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu sao lưu (tối thiểu 10 ký tự)',
              ),
            ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => run(save),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu cấu hình'),
              ),
              FilledButton.icon(
                onPressed: () => run(create),
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Sao lưu ngay'),
              ),
              OutlinedButton.icon(
                onPressed: () => run(restore),
                icon: const Icon(Icons.restore),
                label: const Text('Khôi phục từ tệp'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'Lịch sử sao lưu',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final row in records)
            Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(
                  row['encrypted'] == 1
                      ? Icons.lock_outline
                      : Icons.folder_zip_outlined,
                ),
                title: Text(
                  (row['filename'] as String).split(RegExp(r'[/\\]')).last,
                ),
                subtitle: Text('${row['created_at']} · ${row['status']}'),
                trailing: row['status'] == 'success'
                    ? TextButton(
                        onPressed: () => run(() async {
                          await widget.service.backup!.verify(
                            row['filename'] as String,
                            password: encrypted ? password.text : null,
                          );
                          message(
                            'Bản sao lưu đã vượt qua kiểm tra khôi phục thử.',
                          );
                        }),
                        child: const Text('Kiểm tra'),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
