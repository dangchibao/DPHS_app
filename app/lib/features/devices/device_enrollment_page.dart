import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';
import '../../core/sync/cloud_api.dart';
import '../../core/auth/device_identity.dart';
import 'device_enrollment_service.dart';

class DeviceEnrollmentPage extends StatefulWidget {
  const DeviceEnrollmentPage({
    super.key,
    required this.service,
    required this.onComplete,
  });
  final LocalService service;
  final VoidCallback onComplete;
  @override
  State<DeviceEnrollmentPage> createState() => _DeviceEnrollmentPageState();
}

class _DeviceEnrollmentPageState extends State<DeviceEnrollmentPage> {
  final endpoint = TextEditingController(), token = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    endpoint.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => busy = true);
    final api = CloudApi(endpoint.text);
    try {
      await widget.service.enrollInstallation(
        api,
        token.text,
        await installationId(),
      );
      widget.service.backupScheduler?.dispose();
      await widget.service.syncEngine?.pauseAndDrain();
      await widget.service.db.close();
      if (mounted) widget.onComplete();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      api.client.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Đăng ký thiết bị')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Chủ hệ thống tạo mã đăng ký cho chi nhánh và máy tại mục Cửa hàng · thiết bị. Mã dùng trong 1 giờ, gắn riêng với bản cài này. Sau khi đăng ký, chờ chủ duyệt rồi đăng nhập bằng tài khoản được phân công.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: endpoint,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ API HTTPS',
                    hintText: 'https://...workers.dev',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: token,
                  enabled: !busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mã đăng ký thiết bị',
                  ),
                ),
                const SizedBox(height: 16),
                if (error != null)
                  SelectableText(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(busy ? 'Đang đăng ký…' : 'Đăng ký bản cài này'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
