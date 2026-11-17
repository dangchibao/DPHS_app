import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';

import 'fixtures.dart';

class _ReconnectApi extends CloudApi {
  _ReconnectApi({required super.client}) : super('http://test');
  int reconnects = 0;
  @override
  bool get hasPendingLogin => token == null;
  @override
  Future<String?> syncTokenFor(
    String user,
    String store,
    String device,
  ) async => 'sync';
  @override
  Future<Map<String, Object?>?> reconnect() async {
    reconnects++;
    token = 'interactive';
    return {
      'user': {'id': 'u1', 'name': 'Chủ online', 'role': 'owner'},
      'store_id': 'store-cn01',
      'device_id': 'device-a2',
      'expires_at': '2026-11-22T00:00:00.000Z',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Sync tự nối lại phiên offline, cập nhật lease và đẩy hàng đợi đúng một lần', () async {
    final service = await salesFixture();
    await service.db.execute(
      "INSERT INTO employee_store_assignments VALUES ('a1','store-cn01','u1','owner',1,'2026-11-15')",
    );
    var pushes = 0;
    final api = _ReconnectApi(
      client: MockClient((request) async {
        Map<String, Object?> response;
        if (request.url.path == '/directory') {
          response = {'stores': [], 'devices': [], 'users': []};
        } else if (request.url.path == '/sync/push') {
          pushes++;
          response = {
            'acknowledged': [
              for (final row
                  in (jsonDecode(request.body) as Map)['mutations'] as List)
                row['id'],
            ],
          };
        } else {
          response = {'cursor': 0, 'events': [], 'has_more': false};
        }
        return http.Response(jsonEncode(response), 200);
      }),
    );
    final engine = SyncEngine(service, api);
    try {
      engine.start();
      await engine.sync();
      expect(engine.status, SyncStatus.synced, reason: engine.detail);
      expect(engine.pending, 0);
      expect(service.session!.name, 'Chủ online');
      expect(service.session!.expiresAt, DateTime.utc(2026, 11, 22));
      expect(
        (await service.db.rows("SELECT password_hash FROM users WHERE id='u1'"))
            .single['password_hash'],
        'hash',
      );
      expect(
        (await service.db.rows(
          "SELECT value FROM local_settings WHERE key='grant:u1'",
        )).single['value'],
        '2026-11-22T00:00:00.000Z',
      );
      final firstPushes = pushes;
      await engine.sync();
      expect(api.reconnects, 1);
      expect(pushes, firstPushes);
    } finally {
      engine.dispose();
      await service.db.close();
    }
  });
}
