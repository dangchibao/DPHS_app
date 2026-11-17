import 'package:material_ui/material_ui.dart';

import '../../core/auth/permissions.dart';
import '../../core/local_service.dart';
import '../devices/device_enrollment_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.service,
    required this.onLogin,
    this.onReconfigure,
  });
  final LocalService service;
  final void Function(LocalSession) onLogin;
  final VoidCallback? onReconfigure;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(text: 'admin'),
      password = TextEditingController();
  bool busy = false, obscure = true;
  String? error;
  bool? initialized;
  @override
  void initState() {
    super.initState();
    widget.service.initialized.then((value) {
      if (mounted) setState(() => initialized = value);
    });
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || initialized == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!initialized!) {
        await widget.service.bootstrap(password.text);
        initialized = true;
      }
      final session = await widget.service.login(username.text, password.text);
      widget.service.syncEngine?.start();
      if (mounted) widget.onLogin(session);
    } catch (e) {
      widget.service.syncEngine?.api.cancelPendingLogin();
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (constraints.maxWidth >= 960)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff103d83), Color(0xff1a72d4)],
                  ),
                ),
                padding: const EdgeInsets.all(64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'ĐỒNG PHỤC\nNGỌC THANH',
                      style: TextStyle(
                        fontSize: 40,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Chăm chút từng bộ đồng phục.\nĐồng hành cùng mỗi năm học.',
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.6,
                        color: Color(0xffdcecff),
                      ),
                    ),
                    const SizedBox(height: 48),
                    const Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Badge(Icons.point_of_sale, 'Bán hàng nhanh'),
                        _Badge(Icons.inventory_2_outlined, 'Kho chính xác'),
                        _Badge(Icons.cloud_done_outlined, 'Làm việc offline'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chào bạn,',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        initialized == false
                            ? 'Khởi tạo dữ liệu mẫu trên thiết bị này'
                            : 'Đăng nhập để bắt đầu một ngày làm việc',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xff64748b),
                        ),
                      ),
                      const SizedBox(height: 36),
                      TextField(
                        controller: username,
                        enabled: !busy && initialized != false,
                        decoration: const InputDecoration(
                          labelText: 'Tài khoản',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: password,
                        enabled: !busy,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: initialized == false
                              ? 'Mật khẩu quản trị (tối thiểu 10 ký tự)'
                              : 'Mật khẩu',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 20),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy || initialized == null
                              ? null
                              : submit,
                          child: busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  initialized == false
                                      ? 'Khởi tạo và thử nghiệm'
                                      : 'Đăng nhập',
                                ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (initialized == false && widget.onReconfigure != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => DeviceEnrollmentPage(
                                        service: widget.service,
                                        onComplete: () {
                                          Navigator.of(context)
                                              .popUntil((r) => r.isFirst);
                                          widget.onReconfigure!();
                                        },
                                      ),
                                    ),
                                  ),
                            child: const Text(
                              'Kết nối chi nhánh · đăng ký máy mới',
                            ),
                          ),
                        ),
                      const Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 18,
                            color: Color(0xff64748b),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Dữ liệu được lưu trên thiết bị của cửa hàng.',
                              style: TextStyle(color: Color(0xff64748b)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 18, color: const Color(0xff145bb0)),
    label: Text(text),
    side: BorderSide.none,
  );
}
