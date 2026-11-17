import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/employees/payroll_service.dart';
import 'package:ngoc_thanh_pos/features/employees/payroll_calculation.dart';

import 'payroll_fixtures.dart';

class _Api extends CloudApi {
  _Api({required super.client}) : super('http://test');
  @override
  Future<String?> syncTokenFor(
    String user,
    String store,
    String device,
  ) async => 'sync-$user';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Nhận snapshot lương vào cursor riêng; từ chối dữ liệu lương trong kênh bán hàng', () async {
    final s = await payrollFixture(withRun: true);
    addTearDown(s.db.close);
    final original = (await s.db.rows(
      "SELECT * FROM payroll_runs WHERE id='run1'",
    )).single;
    final row = {...original, 'id': 'run-server'};
    var leak = false;
    final api = _Api(
      client: MockClient((request) async {
        Object response;
        if (request.url.path == '/directory') {
          response = {'stores': [], 'devices': [], 'users': []};
        } else if (request.url.path == '/sync/push') {
          response = {
            'acknowledged': [
              for (final m
                  in (jsonDecode(request.body) as Map)['mutations'] as List)
                m['id'],
            ],
          };
        } else if (request.url.path == '/payroll/pull') {
          response = {
            'cursor': 5,
            'has_more': false,
            'events': [
              {'entity_type': 'payroll_runs', 'payload': jsonEncode(row)},
            ],
          };
        } else if (leak && request.url.queryParameters['scope'] == 'store') {
          response = {
            'cursor': 6,
            'has_more': false,
            'events': [
              {
                'entity_type': 'payroll_runs',
                'payload': jsonEncode({...row, 'id': 'leaked'}),
              },
            ],
          };
        } else {
          response = {'cursor': 0, 'events': [], 'has_more': false};
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..token = 'interactive';
    final engine = SyncEngine(s, api);
    addTearDown(engine.dispose);
    engine.start();
    await engine.sync();
    expect(engine.status, SyncStatus.synced, reason: engine.detail);
    expect(
      (await s.db.rows('SELECT * FROM payroll_runs WHERE id=?', [
        'run-server',
      ])).single,
      row,
    );
    expect(
      (await s.db.rows('SELECT server_seq FROM sync_cursors WHERE store_id=?', [
        'payroll:${s.storeId}',
      ])).single['server_seq'],
      5,
    );
    leak = true;
    await engine.sync();
    expect(engine.status, SyncStatus.conflict);
    expect(
      await s.db.rows("SELECT id FROM payroll_runs WHERE id='leaked'"),
      isEmpty,
    );
    expect(
      (await s.db.rows('SELECT server_seq FROM sync_cursors WHERE store_id=?', [
        s.storeId,
      ])).single['server_seq'],
      0,
    );
  });
  test('Route private một command/request; chỉ vai trò lương kéo feed; checkpoint tối đa ngày', () async {
    final s = await payrollFixture();
    addTearDown(s.db.close);
    await s.saveCompensation(
      employee: 'u1',
      month: '2026-12',
      rule: CompensationRule.fromJson(payrollRuleJson()),
    );
    var privatePushes = 0, privatePulls = 0, checkpoints = 0;
    final api = _Api(
      client: MockClient((request) async {
        Object response;
        if (request.url.path == '/directory') {
          response = {
            'stores': [],
            'devices': [],
            'users': [],
            'schema_version': 22,
          };
        } else if (request.url.path.endsWith('/push')) {
          final rows = (jsonDecode(request.body) as Map)['mutations'] as List;
          if (request.url.path == '/payroll/push') {
            privatePushes++;
            expect(rows, hasLength(1));
            expect(
              (rows.single['records'] as List).single['table'],
              'payroll_commands',
            );
            expect(request.headers['Authorization'], 'Bearer sync-u1');
          } else {
            expect(jsonEncode(rows), isNot(contains('payroll_commands')));
          }
          response = {
            'acknowledged': [for (final row in rows) row['id']],
          };
        } else if (request.url.path == '/sync/checkpoint') {
          checkpoints++;
          response = {'received_at': '2026-11-15T00:00:00.000Z'};
        } else {
          if (request.url.path == '/payroll/pull') {
            privatePulls++;
          }
          response = {'events': [], 'cursor': 0, 'has_more': false};
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..token = 'interactive';
    final engine = SyncEngine(s, api);
    addTearDown(engine.dispose);
    engine.start();
    await engine.sync();
    expect(engine.status, SyncStatus.synced, reason: engine.detail);
    expect(privatePushes, 1);
    expect(privatePulls, 1);
    expect(checkpoints, 1);
    await engine.sync();
    expect(checkpoints, 1);
    final owner = s.session!;
    s.session = LocalSession(
      userId: owner.userId,
      name: owner.name,
      role: Role.cashier,
      storeId: owner.storeId,
      deviceId: owner.deviceId,
      expiresAt: owner.expiresAt,
    );
    final before = privatePulls;
    await engine.sync();
    expect(privatePulls, before);
  });
}
