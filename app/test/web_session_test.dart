import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/web/web_session.dart';
import 'package:ngoc_thanh_pos/features/web/web_portal.dart';

Map<String, Object?> response(DateTime now) => {
  'user': {'id': 'u1', 'name': 'Chủ', 'role': 'owner'},
  'store_id': 's1',
  'device_id': 'w1',
  'expires_at': now.add(const Duration(hours: 8)).toIso8601String(),
};
void main() {
  test('Phiên Web xóa quyền và dữ liệu khi thu hồi, đổi role, mất mạng hoặc hết hạn', () async {
    final now = DateTime.utc(2026, 11, 17);
    for (final mode in ['revoked', 'role', 'offline', 'expired']) {
      final api = CloudApi(
        'https://fixture.test',
        client: MockClient((request) async {
          if (mode == 'offline') throw http.ClientException('offline');
          if (mode == 'revoked') {
            return http.Response(
              jsonEncode({'error': 'Thu hồi', 'code': 'UNAUTHENTICATED'}),
              401,
            );
          }
          return http.Response(
            jsonEncode({
              'device_kind': 'web',
              'user_id': 'u1',
              'role': 'cashier',
              'store_id': 's1',
              'device_id': 'w1',
            }),
            200,
          );
        }),
      );
      var clock = now;
      final session = WebSession(api, clock: () => clock);
      api.token = 'fixture-token';
      session.accept(response(now));
      expect(session.can(Permission.reports), isTrue);
      if (mode == 'expired') clock = now.add(const Duration(hours: 9));
      await session.verify();
      expect(session.active, isFalse, reason: mode);
      expect(session.user, isNull);
      expect(api.token, isNull);
      session.dispose();
      api.close();
    }
  });
  test('Đăng xuất Web xóa dữ liệu ngay cả khi server không trả lời', () async {
    final api = CloudApi(
      'https://fixture.test',
      client: MockClient(
        (request) async => throw http.ClientException('offline'),
      ),
    );
    final now = DateTime.utc(2026, 11, 17),
        session = WebSession(api, clock: () => DateTime.utc(2026, 11, 17));
    api.token = 'fixture-token';
    session.accept(response(now));
    final pending = session.logout();
    expect(session.user, isNull);
    expect(api.token, isNull);
    await pending;
    session.dispose();
    api.close();
  });
  test('Đăng nhập Web dùng challenge/KDF, không gọi login native hoặc lưu sync token', () async {
    final paths = <String>[];
    final now = DateTime.utc(2026, 11, 17);
    final api = CloudApi(
      'https://fixture.test',
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/auth/challenge') {
          return http.Response(
            jsonEncode({
              'salt': 'a' * 64,
              'algorithm': 'PBKDF2-SHA256',
              'iterations': 600000,
            }),
            200,
          );
        }
        final body = jsonDecode(request.body) as Map;
        expect(body['credential'], matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(body.containsKey('password'), isFalse);
        expect(body['installation_id'], 'browser-fixture');
        return http.Response(
          jsonEncode({...response(now), 'token': 'b' * 64}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    await api.loginWeb(
      'admin',
      'fixture-password-only',
      's1',
      'w1',
      installation: 'browser-fixture',
    );
    expect(paths, ['/auth/challenge', '/auth/web/login']);
    expect(api.token, 'b' * 64);
  });
  testWidgets(
    'Đăng nhập Web mobile hiển thị cấu hình thật, không có POS offline',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: WebPortal()));
      await tester.pumpAndSettle();
      expect(find.text('Đồng phục Ngọc Thanh'), findsOneWidget);
      expect(find.text('Địa chỉ API HTTPS'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Đăng nhập online'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Đăng nhập online'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
