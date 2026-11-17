import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import 'personnel_service.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key, required this.service});
  final LocalService service;
  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  late Future<List<Map<String, Object?>>> entries;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    entries = widget.service.employees();
  }

  Future<void> edit([Map<String, Object?>? user]) async {
    final username = TextEditingController(
          text: user?['username'] as String? ?? '',
        ),
        name = TextEditingController(
          text: user?['display_name'] as String? ?? '',
        ),
        password = TextEditingController(),
        reason = TextEditingController();
    var role = Role.values.byName(user?['role'] as String? ?? 'cashier');
    var active = user?['active'] != 0;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            user == null
                ? 'Tạo tài khoản nhân viên'
                : 'Phân quyền / vị trí nhân viên',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: username,
                    enabled: user == null,
                    decoration: const InputDecoration(labelText: 'Tài khoản'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Họ tên'),
                  ),
                  const SizedBox(height: 14),
                  if (user == null) ...[
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu (tối thiểu 10 ký tự)',
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  DropdownButtonFormField<Role>(
                    initialValue: role,
                    decoration: const InputDecoration(
                      labelText: 'Vai trò / vị trí',
                    ),
                    items: [
                      for (final r in Role.values)
                        DropdownMenuItem(value: r, child: Text(roleLabels[r]!)),
                    ],
                    onChanged: (value) => role = value!,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Đang làm việc'),
                    subtitle: const Text('Tắt để khóa tài khoản, giữ lịch sử'),
                    value: active,
                    onChanged: (value) => setDialogState(() => active = value),
                  ),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Lý do thay đổi (bắt buộc)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        await widget.service.saveEmployee(
          id: user?['id'] as String?,
          username: username.text,
          name: name.text,
          role: role,
          password: password.text,
          reason: reason.text,
          active: active,
        );
        if (mounted) setState(reload);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
    username.dispose();
    name.dispose();
    password.dispose();
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Nhân viên & phân quyền',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.icon(
              onPressed: () => edit(),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Thêm nhân viên'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: FutureBuilder(
            future: entries,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('${snapshot.error}');
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView.separated(
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final user = snapshot.data![index];
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(user['display_name'] as String),
                      subtitle: Text(
                        '${user['username']} · ${roleLabels[Role.values.byName(user['role'] as String)]} · ${user['active'] == 1 ? 'Đang làm việc' : 'Đã khóa'}',
                      ),
                      trailing: IconButton(
                        onPressed: () => edit(user),
                        icon: const Icon(Icons.manage_accounts_outlined),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
