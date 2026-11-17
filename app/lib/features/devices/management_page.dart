import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';

class ManagementPage extends StatefulWidget {
  const ManagementPage({super.key, required this.service});
  final LocalService service;
  @override
  State<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
  List<Map<String, Object?>> stores = [],
      devices = [],
      users = [],
      assignments = [];
  String? selected, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<Map<String, Object?>> request([Map<String, Object?>? body]) async {
    widget.service.require(Permission.configure);
    final api = widget.service.syncEngine?.api;
    if (api == null) {
      throw StateError(
        'Cần kết nối API và đăng nhập online để quản trị hệ thống.',
      );
    }
    return api.send('/management', body: body);
  }

  Future<void> load() async {
    if (mounted) setState(() => busy = true);
    try {
      final result = await request();
      List<Map<String, Object?>> list(String key) => (result[key] as List)
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList();
      if (mounted) {
        setState(() {
          stores = list('stores');
          devices = list('devices');
          users = list('users');
          assignments = list('assignments');
          selected ??= stores.firstOrNull?['id'] as String?;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, String>?> form(
    String title,
    List<(String, String)> fields,
  ) => showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _ManagementForm(title: title, fields: fields),
  );
  Future<void> mutate(Map<String, Object?> body) async {
    setState(() => busy = true);
    try {
      final result = await request(body);
      if (result['token'] != null && mounted) {
        final token = result['token'] as String;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Mã đăng ký máy mới'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mã chỉ hiện một lần, hiệu lực 1 giờ. Nhập trên máy mới rồi tải lại danh sách để duyệt. Không gửi mã cho người khác.',
                    ),
                    const SizedBox(height: 16),
                    SelectableText(token),
                    Text('API: ${widget.service.syncEngine!.api.baseUrl}'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: token)),
                child: const Text('Sao chép mã'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đã lưu mã'),
              ),
            ],
          ),
        );
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createStore() async {
    final values = await form('Thêm cửa hàng', [
      ('code', 'Mã (NT-CN02)'),
      ('name', 'Tên cửa hàng'),
      ('reason', 'Lý do'),
    ]);
    if (values == null || !mounted) return;
    await mutate({
      'action': 'create_store',
      'id': widget.service.uuid.v7(),
      'assignment_id': widget.service.uuid.v7(),
      ...values,
    });
  }

  Future<void> invite() async {
    final values = await form('Đăng ký máy tại chi nhánh', [
      ('code', 'Mã máy (B3, không tái dùng)'),
      ('name', 'Tên máy'),
      ('reason', 'Lý do'),
    ]);
    if (values == null || !mounted) return;
    await mutate({
      'action': 'invite_device',
      'id': widget.service.uuid.v7(),
      'enrollment_id': widget.service.uuid.v7(),
      'store_id': selected,
      ...values,
    });
  }

  Future<void> status(Map<String, Object?> d, String status) async {
    final values = await form(
      status == 'approved'
          ? 'Duyệt máy đã đăng ký'
          : 'Thu hồi vĩnh viễn · đồng bộ hết giao dịch trước',
      [('reason', 'Lý do')],
    );
    if (values == null || !mounted) return;
    await mutate({
      'action': 'set_device',
      'id': d['id'],
      'store_id': d['store_id'],
      'status': status,
      ...values,
    });
  }

  Future<void> assign() async {
    final choice = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _AssignmentForm(users: users),
    );
    if (choice == null || !mounted) return;
    await mutate({
      'action': 'assign_staff',
      'id': widget.service.uuid.v7(),
      'store_id': selected,
      ...choice,
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Cửa hàng · thiết bị',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      const Text(
        'Quản trị online dành cho chủ. Máy mới phải nhận mã đăng ký và được duyệt. Thu hồi máy chặn các phiên cloud; máy offline biết thay đổi khi kết nối lại hoặc lease hết hạn. Đồng bộ hết giao dịch trước khi thu hồi.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: busy ? null : createStore,
            child: const Text('Thêm cửa hàng'),
          ),
          OutlinedButton(
            onPressed: busy ? null : load,
            child: const Text('Tải lại'),
          ),
        ],
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SelectableText(
            error!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      if (busy) const LinearProgressIndicator(),
      const SizedBox(height: 16),
      if (stores.isNotEmpty)
        DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Chi nhánh'),
          items: [
            for (final s in stores)
              DropdownMenuItem(
                value: s['id'] as String,
                child: Text('${s['code']} · ${s['name']}'),
              ),
          ],
          onChanged: busy ? null : (v) => setState(() => selected = v),
        ),
      const SizedBox(height: 16),
      if (selected != null)
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : invite,
              icon: const Icon(Icons.add),
              label: const Text('Mời máy mới'),
            ),
            OutlinedButton(
              onPressed: busy ? null : assign,
              child: const Text('Gán nhân viên vào chi nhánh'),
            ),
          ],
        ),
      const SizedBox(height: 16),
      for (final d in devices.where((d) => d['store_id'] == selected))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d['code']} · ${d['name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  d['status'] == 'revoked'
                      ? 'Đã thu hồi'
                      : d['status'] == 'approved'
                      ? 'Đã duyệt'
                      : d['claimed'] == 1
                      ? 'Đã đăng ký · chờ duyệt'
                      : 'Chờ máy nhận mã đăng ký',
                ),
                if (d['id'] != widget.service.deviceId &&
                    d['status'] != 'revoked')
                  Wrap(
                    spacing: 12,
                    children: [
                      if (d['status'] == 'pending' && d['claimed'] == 1)
                        FilledButton(
                          onPressed: busy ? null : () => status(d, 'approved'),
                          child: const Text('Duyệt máy'),
                        ),
                      TextButton(
                        onPressed: busy ? null : () => status(d, 'revoked'),
                        child: const Text('Thu hồi máy'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      const Text(
        'Nhân viên tại chi nhánh',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      for (final a in assignments.where((a) => a['store_id'] == selected))
        ListTile(
          title: Text(
            users
                        .where((u) => u['id'] == a['user_id'])
                        .firstOrNull?['display_name']
                    as String? ??
                a['user_id'] as String,
          ),
          subtitle: Text(
            '${_roleName(a['role'] as String)} · ${a['active'] == 1 ? 'Đang phân công' : 'Đã ngừng'}',
          ),
        ),
    ],
  );
}

String _roleName(String value) => switch (value) {
  'owner' => 'Chủ hệ thống',
  'manager' => 'Quản lý',
  'cashier' => 'Thu ngân',
  'warehouse' => 'Kho',
  'accountant' => 'Kế toán',
  _ => value,
};

class _ManagementForm extends StatefulWidget {
  const _ManagementForm({required this.title, required this.fields});
  final String title;
  final List<(String, String)> fields;
  @override
  State<_ManagementForm> createState() => _ManagementFormState();
}

class _ManagementFormState extends State<_ManagementForm> {
  late final fields = {
    for (final f in widget.fields) f.$1: TextEditingController(),
  };
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: fields[f.$1],
                  maxLength: 200,
                  decoration: InputDecoration(labelText: f.$2),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Quay lại'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          for (final f in fields.entries) f.key: f.value.text.trim(),
        }),
        child: const Text('Xác nhận'),
      ),
    ],
  );
}

class _AssignmentForm extends StatefulWidget {
  const _AssignmentForm({required this.users});
  final List<Map<String, Object?>> users;
  @override
  State<_AssignmentForm> createState() => _AssignmentFormState();
}

class _AssignmentFormState extends State<_AssignmentForm> {
  String? user;
  String role = 'cashier';
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Gán nhân viên vào chi nhánh'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Nhân viên'),
              items: [
                for (final u in widget.users.where((u) => u['active'] == 1))
                  DropdownMenuItem(
                    value: u['id'] as String,
                    child: Text('${u['display_name']} · ${u['username']}'),
                  ),
              ],
              onChanged: (v) => setState(() => user = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Vai trò'),
              items: [
                for (final r in Role.values)
                  DropdownMenuItem(
                    value: r.name,
                    child: Text(_roleName(r.name)),
                  ),
              ],
              onChanged: (v) => setState(() => role = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Lý do'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Quay lại'),
      ),
      FilledButton(
        onPressed: user == null
            ? null
            : () => Navigator.pop(context, {
                'user_id': user,
                'role': role,
                'reason': reason.text.trim(),
              }),
        child: const Text('Gán chi nhánh'),
      ),
    ],
  );
}
