import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';

void main() {
  test(
    'Gửi schema hiện hành để server phát hiện client cần cập nhật',
    () async {
      final api = CloudApi(
        'https://test.invalid',
        client: MockClient((request) async {
          expect(
            request.headers['X-Client-Schema'],
            '${AppDatabase.currentSchemaVersion}',
          );
          return http.Response('{}', 200);
        }),
      );
      try {
        await api.send('/sync/pull');
      } finally {
        api.close();
      }
    },
  );
  test('HTML Cloudflare 1027/1102 được nhận diện riêng với mất mạng', () async {
    for (final testCase in [
      ('1027', 'CLOUD_LIMIT'),
      ('1102', 'CLOUD_CPU_LIMIT'),
    ]) {
      final api = CloudApi(
        'https://test.invalid/',
        client: MockClient(
          (_) async =>
              http.Response('<html><h1>Error ${testCase.$1}</h1></html>', 503),
        ),
      );
      try {
        await expectLater(
          api.send('/health', authenticated: false),
          throwsA(isA<CloudError>().having((e) => e.code, 'code', testCase.$2)),
        );
      } finally {
        api.close();
      }
    }
  });
  test('Bản release yêu cầu HTTPS cho cloud và từ chối URL chứa thông tin đăng nhập', () {
    expect(
      cloudEndpoint('https://api.example.com', '/auth/login').scheme,
      'https',
    );
    expect(cloudEndpoint('http://127.0.0.1:8787', '/health').host, '127.0.0.1');
    expect(
      () => cloudEndpoint('http://api.example.com', '/auth/login'),
      throwsA(
        isA<CloudError>().having((e) => e.code, 'code', 'HTTPS_REQUIRED'),
      ),
    );
    expect(
      () => cloudEndpoint('https://admin:secret@api.example.com', '/health'),
      throwsA(isA<CloudError>()),
    );
  });
}
