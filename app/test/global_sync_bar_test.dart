import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/main.dart';
import 'package:ngoc_thanh_pos/core/providers.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/shell/sync_status_bar.dart';

import 'fixtures.dart';

void main() {
  testWidgets('Thanh đồng bộ vẫn hiện khi mở route và dùng chuột', (
    tester,
  ) async {
    final s = (await tester.runAsync(salesFixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    final engine = SyncEngine(
      s,
      CloudApi(
        'http://test',
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
    );
    s.syncEngine = engine;
    addTearDown(engine.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localServiceProvider.overrideWith((_) async => s)],
        child: const NgocThanhApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SyncStatusBar), findsOneWidget);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Trang kiểm tra')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trang kiểm tra'), findsOneWidget);
    expect(find.byType(SyncStatusBar), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.refresh).last));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });
}
