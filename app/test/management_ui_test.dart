import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/devices/management_page.dart';
import 'package:ngoc_thanh_pos/features/auth/login_page.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:drift/native.dart';

import 'fixtures.dart';

void main() {
  testWidgets('Chủ tạo cửa hàng từ màn quản trị online với UUID client', (
    tester,
  ) async {
    final s = (await tester.runAsync(salesFixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    Map<String, Object?>? submitted;
    final api = CloudApi(
      'https://shop.example',
      client: MockClient((request) async {
        if (request.method == 'POST') {
          submitted = Map<String, Object?>.from(
            jsonDecode(request.body) as Map,
          );
          return http.Response('{"ok":true}', 201);
        }
        return http.Response(
          jsonEncode({
            'stores': [
              {'id': 's1', 'code': 'NT-CN01', 'name': 'Chi nhánh 01'},
            ],
            'devices': [],
            'users': [],
            'assignments': [],
          }),
          200,
        );
      }),
    );
    addTearDown(api.client.close);
    final engine = SyncEngine(s, api);
    s.syncEngine = engine;
    addTearDown(engine.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManagementPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm cửa hàng'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Mã (NT-CN02)'), 'NT-CN02');
    await tester.enterText(field('Tên cửa hàng'), 'Chi nhánh 02');
    await tester.enterText(field('Lý do'), 'Mở chi nhánh');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(submitted?['action'], 'create_store');
    expect(submitted?['id'], matches(r'^[0-9a-f-]{14}7'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Mobile máy chưa có dữ liệu luôn thấy bước đăng ký chi nhánh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final s = LocalService(db);
    await tester.runAsync(() => s.initialized);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(service: s, onLogin: (_) {}, onReconfigure: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('Kết nối chi nhánh · đăng ký máy mới');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Đăng ký bản cài này'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
