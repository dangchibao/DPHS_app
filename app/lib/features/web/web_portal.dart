import 'dart:async';
import 'dart:convert';

import 'web_payroll_page.dart';
import 'web_catalog_page.dart';
import 'web_password_page.dart';
import '../audit/cloud_audit_page.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/device_identity.dart';
import '../../core/auth/permissions.dart';
import '../../core/sync/cloud_api.dart';
import '../../core/export/report_export.dart';
import '../../core/export/xlsx_export.dart';
import '../devices/management_page.dart';
import '../employees/employees_page.dart';
import '../reports/online_reports_page.dart';
import '../reports/report_service.dart';
import 'web_session.dart';
import '../settings/cloud_usage_page.dart';

class WebPortal extends StatefulWidget {
  const WebPortal({super.key, this.apiFactory, this.initialEndpoint});
  final CloudApi Function(String)? apiFactory;
  final String? initialEndpoint;
  @override
  State<WebPortal> createState() => _WebPortalState();
}

class _WebPortalState extends State<WebPortal> {
  final endpoint = TextEditingController(
        text: const String.fromEnvironment('API_URL'),
      ),
      username = TextEditingController(text: 'admin'),
      password = TextEditingController(),
      store = TextEditingController(),
      device = TextEditingController(),
      enrollment = TextEditingController();
  WebSession? session;
  bool busy = false;
  String? error, notice;
  static const storage = FlutterSecureStorage();
  String get endpointUrl =>
      endpoint.text.trim().replaceFirst(RegExp(r'/+$'), '');
  @override
  void initState() {
    super.initState();
    if (widget.initialEndpoint != null) endpoint.text = widget.initialEndpoint!;
    unawaited(restoreIdentity(endpointUrl));
  }

  Future<void> restoreIdentity(String url) async {
    if (url.isEmpty || store.text.isNotEmpty || device.text.isNotEmpty) return;
    try {
      final encoded = await storage.read(key: 'web_identity:$url');
      final saved = encoded == null
          ? {
              'store_id': await storage.read(key: 'web_store:$url'),
              'device_id': await storage.read(key: 'web_device:$url'),
            }
          : jsonDecode(encoded);
      // Loading configuration must not overwrite manual edits or a different
      // endpoint selected while secure storage was being read.
      if (!mounted ||
          endpointUrl != url ||
          store.text.isNotEmpty ||
          device.text.isNotEmpty) {
        return;
      }
      if (saved is Map &&
          saved['store_id'] is String &&
          saved['device_id'] is String &&
          (saved['store_id'] as String).isNotEmpty &&
          (saved['device_id'] as String).isNotEmpty) {
        setState(() {
          store.text = saved['store_id'] as String;
          device.text = saved['device_id'] as String;
        });
      }
    } catch (_) {
      // Corrupt/unavailable local configuration does not prevent entering IDs.
      // Authentication and permissions still come from the online API.
    }
  }

  Future<void> saveIdentity(String url, String storeId, String deviceId) =>
      storage.write(
        key: 'web_identity:$url',
        value: jsonEncode({'store_id': storeId, 'device_id': deviceId}),
      );

  @override
  void dispose() {
    session?.dispose();
    session?.api.close();
    for (final c in [endpoint, username, password, store, device, enrollment]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<WebSession> connection() async {
    final url = endpointUrl;
    cloudEndpoint(url, '/auth/me');
    if (session?.api.baseUrl != url) {
      session?.dispose();
      session?.api.close();
      session = WebSession(widget.apiFactory?.call(url) ?? CloudApi(url));
    }
    await restoreIdentity(url);
    return session!;
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        password.clear();
        setState(() => busy = false);
      }
    }
  }

  Future<void> enroll() => run(() async {
    final s = await connection();
    final response = await s.api.send(
      '/devices/enroll',
      authenticated: false,
      body: {
        'token': enrollment.text.trim(),
        'kind': 'web',
        'installation_id': await installationId(),
      },
    );
    final claimed = Map<String, Object?>.from(response['device'] as Map);
    if (claimed['kind'] != 'web') {
      throw StateError(
        'Mã này dành cho máy bán hàng. Cần chủ mời trình duyệt online.',
      );
    }
    store.text = (response['store'] as Map)['id'] as String;
    device.text = claimed['id'] as String;
    await saveIdentity(s.api.baseUrl, store.text, device.text);
    enrollment.clear();
    notice = claimed['status'] == 'approved'
        ? 'Trình duyệt đã được duyệt. Có thể đăng nhập.'
        : 'Đã đăng ký trình duyệt. Chủ cần duyệt thiết bị trước khi đăng nhập.';
  });
  Future<void> login() => run(() async {
    final s = await connection();
    final response = await s.api.loginWeb(
      username.text.trim(),
      password.text,
      store.text.trim(),
      device.text.trim(),
    );
    if (!mounted) {
      s.api.token = null;
      return;
    }
    try {
      // A single record keeps the two IDs together. No password, token,
      // role or offline grant is persisted by the portal.
      await saveIdentity(
        s.api.baseUrl,
        response['store_id'] as String,
        response['device_id'] as String,
      );
    } catch (_) {
      if (mounted) {
        s.invalidate(
          'Không lưu được cấu hình trình duyệt. Kiểm tra quyền lưu trữ rồi đăng nhập lại.',
        );
      } else {
        s.api.token = null;
      }
      rethrow;
    }
    if (!mounted) {
      s.api.token = null;
      return;
    }
    s.accept(response);
  });
  @override
  Widget build(BuildContext context) {
    final s = session;
    if (s != null) {
      return ListenableBuilder(
        listenable: s,
        builder: (context, _) => s.active
            ? Navigator(
                key: ValueKey(s.api.token),
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => _WebWorkspace(session: s),
                ),
              )
            : loginForm(s.message),
      );
    }
    return loginForm(null);
  }

  Widget loginForm(String? message) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.school_outlined,
              size: 52,
              color: Color(0xff1763c0),
            ),
            const SizedBox(height: 12),
            const Text(
              'Đồng phục Ngọc Thanh',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Quản lý online · Windows/Android dùng ứng dụng để bán khi mất mạng.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: endpoint,
              enabled: !busy,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Địa chỉ API HTTPS'),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Đăng ký trình duyệt lần đầu'),
              children: [
                const Text(
                  'Nhận mã “Mời trình duyệt online” từ chủ, đăng ký tại đây rồi chờ chủ duyệt. Không dùng mã của máy POS.',
                ),
                TextField(
                  controller: enrollment,
                  enabled: !busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mã đăng ký một lần',
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : enroll,
                  child: const Text('Đăng ký trình duyệt'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: store,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'ID cửa hàng (tự điền sau đăng ký)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: device,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'ID trình duyệt đã được duyệt',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: username,
              enabled: !busy,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(labelText: 'Tài khoản'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              enabled: !busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) {
                if (!busy) login();
              },
              decoration: const InputDecoration(labelText: 'Mật khẩu'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : login,
              child: Text(busy ? 'Đang xác thực…' : 'Đăng nhập online'),
            ),
            if (busy) const LinearProgressIndicator(),
            for (final value in [error, notice, message])
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    value,
                    style: TextStyle(color: value == error ? Colors.red : null),
                  ),
                ),
            const SizedBox(height: 12),
            const Text(
              'Phiên chỉ giữ trong bộ nhớ. Tải lại trang hoặc không xác minh được kết nối sẽ cần đăng nhập lại.',
            ),
          ],
        ),
      ),
    ),
  );
}

class _WebWorkspace extends StatefulWidget {
  const _WebWorkspace({required this.session});
  final WebSession session;
  @override
  State<_WebWorkspace> createState() => _WebWorkspaceState();
}

class _WebWorkspaceState extends State<_WebWorkspace>
    with WidgetsBindingObserver {
  int selected = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.session.verify();
  }

  Future<void> export(String name, ReportTable table, bool pdf) async {
    final s = widget.session, expected = s.api.token;
    if (!s.can(Permission.reports)) {
      throw StateError('Phiên không có quyền báo cáo.');
    }
    final bytes = pdf
        ? await buildReportPdf(name, table.headers, table.pdfRows())
        : buildXlsx(
            table.headers,
            table.excelRows(),
            moneyColumns: table.moneyColumns,
          );
    await s.api.send(
      '/reports/export',
      body: {
        'id': const Uuid().v7(),
        'name': name,
        'format': pdf ? 'PDF' : 'XLSX',
      },
    );
    if (!mounted || !s.active || s.api.token != expected) {
      throw StateError('Phiên đã thay đổi.');
    }
    await FilePicker.saveFile(
      fileName: '${safeReportFilename(name)}.${pdf ? 'pdf' : 'xlsx'}',
      bytes: bytes,
      mimeType: pdf
          ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      dialogTitle: 'Lưu báo cáo',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pages = <({String title, Widget child})>[
      if (s.can(Permission.reports))
        (
          title: 'Báo cáo',
          child: OnlineReportsPage(
            api: s.api,
            storeId: s.storeId,
            exportAction: export,
          ),
        ),
      if (s.can(Permission.catalog))
        (
          title: 'Sản phẩm',
          child: WebCatalogPage(
            api: s.api,
            storeId: s.storeId!,
            deviceId: s.deviceId!,
            userId: s.user!['id'] as String,
          ),
        ),
      if (s.can(Permission.payroll))
        (title: 'Lương online', child: WebPayrollPage(api: s.api)),
      if (s.can(Permission.audit))
        (
          title: 'Nhật ký cloud',
          child: CloudAuditPage(
            api: s.api,
            storeId: s.storeId!,
            canArchive: s.can(Permission.configure),
          ),
        ),
      if (s.can(Permission.staff))
        (title: 'Nhân viên', child: EmployeesPage.online(api: s.api)),
      if (s.can(Permission.configure))
        (title: 'Hạn mức cloud', child: CloudUsagePage(api: s.api)),
      if (s.can(Permission.configure))
        (
          title: 'Cửa hàng · thiết bị',
          child: ManagementPage.online(api: s.api, deviceId: s.deviceId),
        ),
      (title: 'Đổi mật khẩu', child: WebPasswordPage(session: s)),
    ];
    final index = selected < pages.length ? selected : 0;
    return Scaffold(
      appBar: AppBar(
        title: Text('${s.user!['name']} · Quản lý online'),
        actions: [
          IconButton(
            onPressed: () => s.verify(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Kiểm tra phiên',
          ),
          IconButton(
            onPressed: () => s.logout(),
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text('Đồng phục Ngọc Thanh'),
                subtitle: Text('Trực tuyến · Không bán offline'),
              ),
              for (var i = 0; i < pages.length; i++)
                ListTile(
                  title: Text(pages[i].title),
                  selected: i == index,
                  onTap: () {
                    setState(() => selected = i);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
      body: pages.isEmpty
          ? const Center(
              child: Text('Vai trò này chưa có chức năng quản lý online.'),
            )
          : KeyedSubtree(
              key: ValueKey(pages[index].title),
              child: pages[index].child,
            ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Chế độ online · Dữ liệu từ cloud',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
