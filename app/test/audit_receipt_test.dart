import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';

import 'fixtures.dart';

class _Api extends CloudApi {
  _Api({required super.client}) : super('http://test');
  @override
  Future<String?> syncTokenFor(
    String user,
    String store,
    String device,
  ) async => 'sync';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Nhận timestamp cloud không sửa nhật ký gốc, cursor quản lý tách riêng',
    () async {
      final service = await salesFixture();
      final audit = (await service.db.rows('SELECT * FROM audit_logs LIMIT 1'))
          .single;
      const received = '2026-11-15T10:00:00.000Z';
      final scopes = <String>[];
      final api = _Api(
        client: MockClient((request) async {
          Map<String, Object?> response;
          if (request.url.path == '/directory') {
            response = {'stores': [], 'devices': [], 'users': []};
          } else if (request.url.path == '/sync/push') {
            response = {
              'acknowledged': [
                for (final row
                    in (jsonDecode(request.body) as Map)['mutations'] as List)
                  row['id'],
              ],
            };
          } else if (request.url.path == '/payroll/pull') {
            response = {'cursor': 0, 'has_more': false, 'events': []};
          } else {
            final scope = request.url.queryParameters['scope']!;
            scopes.add(scope);
            response = {
              'cursor': 7,
              'has_more': false,
              'events': scope == 'audit'
                  ? [
                      {
                        'entity_type': 'audit_logs',
                        'payload': jsonEncode({
                          ...audit,
                          'server_time': received,
                        }),
                      },
                    ]
                  : [],
            };
          }
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..token = 'interactive';
      final engine = SyncEngine(service, api);
      try {
        engine.start();
        await engine.sync();
        expect(engine.status, SyncStatus.synced, reason: engine.detail);
        expect(scopes, contains('audit'));
        expect(
          (await service.db.rows('SELECT * FROM audit_logs WHERE id=?', [
            audit['id'],
          ])).single,
          audit,
        );
        expect(
          (await service.db.rows(
            'SELECT received_at FROM local_audit_receipts WHERE audit_id=?',
            [audit['id']],
          )).single['received_at'],
          received,
        );
        expect(
          (await service.db.rows(
            'SELECT server_seq FROM sync_cursors WHERE store_id=?',
            ['audit:${service.storeId}'],
          )).single['server_seq'],
          7,
        );
      } finally {
        engine.dispose();
        await service.db.close();
      }
    },
  );
}
