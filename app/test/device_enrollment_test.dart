import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/devices/device_enrollment_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Máy mới lưu đúng danh tính và endpoint, không giữ mã đăng ký hay seed sai chi nhánh', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = LocalService(db);
    final api = CloudApi(
      'https://shop.example',
      client: MockClient((request) async {
        expect(request.url.path, '/devices/enroll');
        expect(request.headers['Authorization'], isNull);
        expect(
          jsonDecode(request.body)['installation_id'],
          'installation-unique-123456',
        );
        return http.Response(
          jsonEncode({
            'store': {
              'id': 's2',
              'code': 'NT-CN02',
              'name': 'CN02',
              'active': 1,
              'created_at': '2026-11-15',
            },
            'device': {
              'id': 'd2',
              'store_id': 's2',
              'code': 'B3',
              'name': 'Máy B3',
              'status': 'pending',
              'created_at': '2026-11-15',
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.client.close);
    await service.enrollInstallation(
      api,
      'test-enrollment-token',
      'installation-unique-123456',
    );
    expect(await service.initialized, isTrue);
    expect(await db.rows('SELECT id FROM users'), isEmpty);
    final settings = {
      for (final r in await db.rows('SELECT * FROM local_settings'))
        r['key']: r['value'],
    };
    expect(settings['identity_store'], 's2');
    expect(settings['identity_device'], 'd2');
    expect(settings['cloud_url'], 'https://shop.example');
    expect(jsonEncode(settings), isNot(contains('test-enrollment-token')));
    await expectLater(
      service.bootstrap('test-only-password'),
      throwsStateError,
    );
    expect(
      (await db.rows('SELECT code FROM stores')).single['code'],
      'NT-CN02',
    );
    final registered = LocalService(db, storeId: 's2', deviceId: 'd2');
    registered.onlineLogin = (_, _) async => {
      'expires_at': DateTime.now()
          .add(const Duration(days: 7))
          .toUtc()
          .toIso8601String(),
      'user': {
        'id': 'u2',
        'name': 'Nhân viên CN02',
        'role': 'cashier',
        'must_change_password': false,
      },
    };
    await registered.login('cashier02', 'test-only-password');
    expect(
      (await db.rows('SELECT status FROM devices')).single['status'],
      'approved',
    );
    expect(registered.session!.storeId, 's2');
  });
  test('Không thay danh tính bản cài có người dùng/giao dịch', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    var requested = false;
    final api = CloudApi(
      'https://shop.example',
      client: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.client.close);
    await expectLater(
      s.enrollInstallation(api, 'token', 'installation-unique-123456'),
      throwsStateError,
    );
    expect(requested, isFalse);
  });
}
