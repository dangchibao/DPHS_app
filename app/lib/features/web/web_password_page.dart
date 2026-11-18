import 'package:material_ui/material_ui.dart';

import 'web_session.dart';

class WebPasswordPage extends StatefulWidget {
  const WebPasswordPage({super.key, required this.session});
  final WebSession session;
  @override
  State<WebPasswordPage> createState() => _WebPasswordPageState();
}

class _WebPasswordPageState extends State<WebPasswordPage> {
  final oldPassword = TextEditingController(),
      newPassword = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    oldPassword.dispose();
    newPassword.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (oldPassword.text.isEmpty ||
        newPassword.text.length < 10 ||
        newPassword.text != confirmation.text) {
      setState(
        () => error = 'Nhập mật khẩu cũ, mật khẩu mới ít nhất 10 ký tự và xác nhận trùng khớp.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.api.changePassword(
        oldPassword.text,
        newPassword.text,
      );
      oldPassword.clear();
      newPassword.clear();
      confirmation.clear();
      await widget.session.logout();
      widget.session.invalidate(
        'Đã đổi mật khẩu. Đăng nhập lại bằng mật khẩu mới.',
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Đổi mật khẩu',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          for (final item in [
            (oldPassword, 'Mật khẩu cũ'),
            (newPassword, 'Mật khẩu mới (ít nhất 10 ký tự)'),
            (confirmation, 'Nhập lại mật khẩu mới'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: item.$1,
                obscureText: true,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: item.$2),
              ),
            ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              busy ? 'Đang đổi mật khẩu…' : 'Đổi mật khẩu và đăng xuất',
            ),
          ),
        ],
      ),
    ),
  );
}
