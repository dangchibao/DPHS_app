import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/auth/session_boundary.dart';

import 'fixtures.dart';

class _TestEngine extends SyncEngine {
  _TestEngine(super.service, super.api);
  void changed() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Directory đổi vai trò thì hết lease, xóa grant và dừng trước push/pull',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      await s.db.execute(
        "INSERT INTO local_settings VALUES('grant:u1','2027-01-01T00:00:00.000Z')",
      );
      final api = CloudApi(
        'http://test',
        client: MockClient((request) async {
          expect(request.url.path, '/directory');
          return http.Response(
            jsonEncode({
              'stores': [],
              'devices': [],
              'users': [
                {
                  'id': 'u1',
                  'username': 'admin',
                  'display_name': 'Thu ngân',
                  'active': 1,
                  'must_change_password': 0,
                  'updated_at': s.now,
                  'role': 'cashier',
                  'assignment_active': 1,
                },
              ],
            }),
            200,
          );
        }),
      )..token = 'interactive';
      final engine = SyncEngine(s, api);
      addTearDown(engine.dispose);
      engine.start();
      await engine.sync();
      expect(engine.status, SyncStatus.needsLogin);
      expect(s.session!.expiresAt.isAfter(s.clock()), isFalse);
      expect(
        await s.db.rows("SELECT * FROM local_settings WHERE key='grant:u1'"),
        isEmpty,
      );
      expect((await s.db.rows('SELECT * FROM outbox')).length, 2);
    },
  );
  testWidgets('Hết quyền đóng route đang chứa dữ liệu nhạy cảm', (
    tester,
  ) async {
    final s = (await tester.runAsync(salesFixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    final api = CloudApi(
      'http://test',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final engine = _TestEngine(s, api);
    s.syncEngine = engine;
    addTearDown(engine.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionBoundary(
          service: s,
          active: true,
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Text('Dữ liệu lương riêng')),
                ),
              ),
              child: const Text('Mở trang riêng'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở trang riêng'));
    await tester.pumpAndSettle();
    expect(find.text('Dữ liệu lương riêng'), findsOneWidget);
    s.session = LocalSession(
      userId: 'u1',
      name: 'Thu ngân',
      role: Role.cashier,
      storeId: s.storeId,
      deviceId: s.deviceId,
      expiresAt: s.clock(),
    );
    engine.changed();
    await tester.pumpAndSettle();
    expect(find.text('Dữ liệu lương riêng'), findsNothing);
    expect(find.text('Mở trang riêng'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
