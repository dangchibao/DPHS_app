import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/employees/staff_handoffs_page.dart';

import 'fixtures.dart';

class _Api extends CloudApi {
  _Api(http.Client client) : super('https://fixture.test', client: client);
  @override
  Future<String?> syncTokenFor(
    String user,
    String store,
    String device,
  ) async => 'sync-$user';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fail in [false, true]) {
    test('Freeze xóa grant/dừng quyền; ACK chỉ sau drain thành công: lỗi=$fail', () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      await s.db.execute(
        "INSERT INTO local_settings VALUES('grant:u1','2027-01-01T00:00:00Z')",
      );
      final paths = <String>[];
      var ack = false;
      final api = _Api(
        MockClient((request) async {
          paths.add(request.url.path);
          Object result;
          if (request.url.path == '/directory') {
            result = {
              'stores': [],
              'devices': [],
              'users': [
                {
                  'id': 'u1',
                  'username': 'admin',
                  'display_name': 'Chủ',
                  'active': 1,
                  'must_change_password': 0,
                  'updated_at': '2026-11-15',
                  'role': 'owner',
                  'assignment_active': 1,
                  'frozen': 1,
                },
              ],
              'handoffs': [
                {'id': 'handoff1', 'user_id': 'u1', 'requires_ack': 1},
              ],
            };
          } else if (request.url.path == '/sync/push') {
            if (fail) {
              return http.Response(
                jsonEncode({
                  'code': 'SERVER_ERROR',
                  'error': 'fixture temporary',
                }),
                503,
              );
            }
            result = {
              'acknowledged': [
                for (final m
                    in (jsonDecode(request.body) as Map)['mutations'] as List)
                  (m as Map)['id'],
              ],
            };
          } else if (request.url.path == '/staff/handoffs/ack') {
            expect(await s.db.rows('SELECT id FROM outbox'), isEmpty);
            expect((jsonDecode(request.body) as Map)['drained'], true);
            ack = true;
            result = {'ok': true};
          } else {
            result = {'events': [], 'cursor': 10, 'has_more': false};
          }
          return http.Response(
            jsonEncode(result),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..token = 'interactive';
      final engine = SyncEngine(s, api);
      addTearDown(engine.dispose);
      addTearDown(api.close);
      engine.start();
      await engine.sync();
      expect(
        await s.db.rows("SELECT * FROM local_settings WHERE key='grant:u1'"),
        isEmpty,
      );
      expect(s.session!.expiresAt.isAfter(s.clock()), isFalse);
      expect(
        (await s.db.rows("SELECT active FROM users WHERE id='u1'"))
            .single['active'],
        0,
      );
      expect(ack, !fail);
      expect(paths, isNot(contains('/payroll/pull')));
      expect(paths, isNot(contains('/sync/checkpoint')));
      if (fail) expect(await s.db.rows('SELECT id FROM outbox'), isNotEmpty);
    });
  }
  testWidgets('Bàn giao mobile hiện máy offline và không cho chốt sớm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'store_id': 's1',
            'requests': [
              {
                'id': 'r1',
                'store_id': 's1',
                'user_id': 'u1',
                'name': 'Nhân viên',
                'status': 'pending',
                'global_lock': 0,
                'payload': {
                  'role': 'warehouse',
                  'active': true,
                  'reason': 'Đổi vị trí',
                },
              },
            ],
            'devices': [
              {
                'request_id': 'r1',
                'store_code': 'NT-CN01',
                'code': 'A2',
                'name': 'Máy offline',
                'device_status': 'approved',
                'acked_at': null,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    )..token = 'interactive';
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StaffHandoffsPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Máy offline'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Hoàn tất bàn giao'),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
