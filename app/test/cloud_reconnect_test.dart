import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const salt =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'cloud_salt:https://test.invalid:admin': salt,
      'installation_id': 'test-installation',
    }),
  );
  test(
    'Đăng nhập offline lưu proof trong RAM và tự đăng nhập lại khi có mạng',
    () async {
      var online = false;
      Map<String, dynamic>? submitted;
      final api = CloudApi(
        'https://test.invalid',
        client: MockClient((request) async {
          if (!online) throw http.ClientException('offline');
          if (request.url.path == '/auth/challenge') {
            return http.Response(
              jsonEncode({
                'salt': salt,
                'algorithm': 'PBKDF2-SHA256',
                'iterations': 600000,
              }),
              200,
            );
          }
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'token': 'interactive',
              'sync_token': 'sync',
              'user': {'id': 'u1'},
            }),
            200,
          );
        }),
      );
      try {
        await expectLater(
          api.login('admin', 'password-for-test', 's1', 'd1'),
          throwsA(isA<http.ClientException>()),
        );
        expect(api.hasPendingLogin, true);
        expect(api.token, isNull);
        expect(
          (await api.secure.readAll()).keys.any(
            (key) => key.contains('proof') || key.contains('password'),
          ),
          false,
        );
        online = true;
        await api.reconnect();
        expect(api.hasPendingLogin, false);
        expect(api.token, 'interactive');
        expect(submitted!['credential'], matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(submitted!.containsKey('password'), false);
        expect(submitted!['installation_id'], 'test-installation');
        expect(await api.syncTokenFor('u1', 's1', 'd1'), 'sync');
        expect(await api.reconnect(), isNull);
      } finally {
        api.close();
      }
    },
  );
  test(
    'Salt đã đổi trong lúc offline yêu cầu đăng nhập lại, không gửi proof cũ',
    () async {
      var online = false, submissions = 0;
      final api = CloudApi(
        'https://test.invalid',
        client: MockClient((request) async {
          if (!online) throw http.ClientException('offline');
          if (request.url.path != '/auth/challenge') submissions++;
          return http.Response(
            jsonEncode({
              'salt': 'b' * 64,
              'algorithm': 'PBKDF2-SHA256',
              'iterations': 600000,
            }),
            200,
          );
        }),
      );
      try {
        await expectLater(
          api.login('admin', 'password-for-test', 's1', 'd1'),
          throwsA(isA<http.ClientException>()),
        );
        online = true;
        await expectLater(
          api.reconnect(),
          throwsA(
            isA<CloudError>().having(
              (e) => e.code,
              'code',
              'CREDENTIAL_CHANGED',
            ),
          ),
        );
        expect(api.hasPendingLogin, false);
        expect(submissions, 0);
        expect(api.token, isNull);
      } finally {
        api.close();
      }
    },
  );
}
