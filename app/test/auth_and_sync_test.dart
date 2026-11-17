import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/employees/personnel_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

class _GrantApi extends CloudApi {
  _GrantApi(super.baseUrl, {required super.client});
  @override
  Future<String?> syncTokenFor(
    String user,
    String store,
    String device,
  ) async => 'grant-$user';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Cloud thu hồi phiên thì xóa lease bền vững, giữ hàng đợi trên máy',
    () async {
      final service = await salesFixture();
      await service.db.execute(
        "INSERT INTO local_settings VALUES ('grant:u1','2027-01-01T00:00:00.000Z')",
      );
      final before = await service.db.rows('SELECT id FROM outbox');
      final api = CloudApi(
        'http://test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'UNAUTHENTICATED',
              'error': 'Phiên bị thu hồi',
            }),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      )..token = 'test-token';
      final engine = SyncEngine(service, api);
      try {
        engine.start();
        await engine.sync();
        expect(engine.status, SyncStatus.needsLogin, reason: engine.detail);
        expect(service.session!.expiresAt.isAfter(service.clock()), isFalse);
        expect(
          await service.db.rows(
            "SELECT * FROM local_settings WHERE key='grant:u1'",
          ),
          isEmpty,
        );
        expect(await service.db.rows('SELECT id FROM outbox'), before);
      } finally {
        engine.dispose();
        await service.db.close();
      }
    },
  );
  test('Đổi ca vẫn gửi hàng đợi bằng đúng người tạo, phiên sync tách khỏi phiên giao diện', () async {
    final service = await salesFixture();
    await service.db.execute(
      "INSERT INTO users VALUES ('u2','cashier','Thu ngân','hash','salt',1,0,'2026-11-15')",
    );
    service.session = LocalSession(
      userId: 'u2',
      name: 'Thu ngân',
      role: Role.cashier,
      storeId: service.storeId,
      deviceId: service.deviceId,
      expiresAt: DateTime.utc(2027),
    );
    await service.sell(
      items: [const CartItem('v1', 1)],
      discount: 0,
      received: 100000,
      method: 'cash',
    );
    final headers = <String>[];
    final api =
        _GrantApi(
            'http://test',
            client: MockClient((request) async {
              Map<String, Object?> body;
              if (request.url.path == '/directory') {
                body = {'stores': [], 'devices': [], 'users': []};
              } else if (request.url.path == '/sync/push') {
                headers.add(request.headers['authorization']!);
                final data = jsonDecode(request.body) as Map;
                body = {
                  'acknowledged': [
                    for (final row in data['mutations'] as List) row['id'],
                  ],
                };
              } else {
                body = {'events': [], 'cursor': 0, 'has_more': false};
              }
              return http.Response(
                jsonEncode(body),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          )
          ..token = 'interactive-u2'
          ..currentUserId = 'u2';
    final engine = SyncEngine(service, api);
    try {
      engine.start();
      await engine.sync();
      expect(engine.status, SyncStatus.synced, reason: engine.detail);
      expect(engine.pending, 0);
      expect(headers, containsAll(['Bearer grant-u1', 'Bearer grant-u2']));
      expect(headers, isNot(contains('Bearer interactive-u2')));
    } finally {
      engine.dispose();
      await service.db.close();
    }
  });
  test(
    'Sau đối soát phục hồi, bộ đếm vượt mã đã có trước khi được bán lại',
    () async {
      final service = await salesFixture();
      await service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 100000,
        method: 'cash',
      );
      await service.db.execute('DELETE FROM document_counters');
      await service.db.execute(
        "INSERT INTO local_settings VALUES ('restore_blocked','1')",
      );
      await service.db.execute(
        "INSERT INTO local_settings VALUES ('restore_reason','restore')",
      );
      service.restoreBlocked = true;
      final api =
          _GrantApi(
              'http://test',
              client: MockClient((request) async {
                final body = request.url.path == '/directory'
                    ? {'stores': [], 'devices': [], 'users': []}
                    : request.url.path == '/sync/push'
                    ? {
                        'acknowledged': [
                          for (final row
                              in (jsonDecode(request.body) as Map)['mutations']
                                  as List)
                            row['id'],
                        ],
                      }
                    : {'events': [], 'cursor': 0, 'has_more': false};
                return http.Response(
                  jsonEncode(body),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }),
            )
            ..token = 'interactive-u1'
            ..currentUserId = 'u1';
      final engine = SyncEngine(service, api);
      try {
        engine.start();
        await engine.sync();
        expect(service.restoreBlocked, false, reason: engine.detail);
        final sale = await service.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 100000,
          method: 'cash',
        );
        expect(sale.code.endsWith('-002'), true);
      } finally {
        engine.dispose();
        await service.db.close();
      }
    },
  );
  test(
    'Bootstrap, đăng nhập, cấp quyền, khóa tài khoản và lease không tự gia hạn',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      var now = DateTime.utc(2026, 11, 15);
      final service = LocalService(db, clock: () => now);
      try {
        await service.bootstrap('password-for-tests-only');
        expect(await service.initialized, true);
        final first = await service.login('admin', 'password-for-tests-only');
        expect(first.role, Role.owner);
        expect((await service.catalog()).length, 15);
        expect(await db.rows('SELECT id FROM schools'), hasLength(2));
        expect(await db.rows('SELECT id FROM students'), hasLength(2));
        expect(await db.rows('SELECT id FROM combo_rules'), hasLength(1));
        await service.saveEmployee(
          username: 'cashier',
          name: 'Thu ngân thử',
          role: Role.cashier,
          password: 'cashier-for-tests-only',
          reason: 'Tạo nhân viên',
        );
        service.session = null;
        final cashier = await service.login(
          'cashier',
          'cashier-for-tests-only',
        );
        expect(
          () => cashier.require(
            Permission.stock,
            LocalService.defaultStoreId,
            now,
          ),
          throwsStateError,
        );
        now = now.add(const Duration(days: 8));
        service.session = null;
        await expectLater(
          service.login('admin', 'password-for-tests-only'),
          throwsStateError,
        );
      } finally {
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('Quota không làm mất outbox; poll không vượt backoff', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.execute(
      "INSERT INTO outbox(id,store_id,device_id,entity_type,payload,priority,created_at) VALUES ('job1','store-cn01','device-a2','audit','[]',1,'2026-11-15')",
    );
    var requests = 0;
    final api = CloudApi(
      'http://test',
      client: MockClient((request) async {
        requests++;
        if (request.url.path == '/directory') {
          return http.Response(
            jsonEncode({'stores': [], 'devices': [], 'users': []}),
            200,
          );
        }
        return http.Response(
          jsonEncode({'code': 'CLOUD_LIMIT', 'error': 'Cloud đạt giới hạn'}),
          503,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..token = 'token-for-test';
    final engine = SyncEngine(LocalService(db), api);
    try {
      engine.start();
      await engine.sync();
      expect(engine.status, SyncStatus.cloudLimit, reason: engine.detail);
      expect(engine.pending, 1);
      expect(engine.nextRetryAt, isNotNull);
      final before = requests;
      await engine.sync();
      expect(requests, before);
      expect((await db.rows('SELECT * FROM outbox')).length, 1);
    } finally {
      engine.dispose();
      await db.close();
    }
  });
}
