import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/web/web_session.dart';
import 'package:ngoc_thanh_pos/features/web/web_password_page.dart';

class _Api extends CloudApi {
  _Api() : super('https://fixture.test');
  int calls = 0;
  bool loggedOut = false;
  @override
  Future<Map<String, Object?>> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    expect(oldPassword, 'old-password');
    expect(newPassword, 'new-password-123');
    calls++;
    return {'ok': true};
  }

  @override
  Future<Map<String, Object?>> send(
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
    String? tokenOverride,
  }) async {
    expect(path, '/auth/logout');
    loggedOut = true;
    return {'ok': true};
  }
}

void main() {
  testWidgets(
    'Web kiểm tra mật khẩu trước khi gửi, đổi thành công xóa phiên và các ô bí mật',
    (tester) async {
      final api = _Api()..token = 'fixture';
      final session = WebSession(api);
      session.accept({
        'user': {'id': 'u1', 'name': 'Chủ', 'role': 'owner'},
        'store_id': 's1',
        'device_id': 'd1',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });
      addTearDown(session.dispose);
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WebPasswordPage(session: session)),
        ),
      );
      await tester.tap(find.text('Đổi mật khẩu và đăng xuất'));
      await tester.pump();
      expect(api.calls, 0);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'old-password');
      await tester.enterText(fields.at(1), 'new-password-123');
      await tester.enterText(fields.at(2), 'new-password-123');
      await tester.tap(find.text('Đổi mật khẩu và đăng xuất'));
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(api.loggedOut, true);
      expect(session.active, false);
      for (final field in tester.widgetList<TextField>(fields)) {
        expect(field.controller!.text, isEmpty);
      }
      expect(session.message, contains('Đã đổi mật khẩu'));
    },
  );
}
