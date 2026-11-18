import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/settings/cloud_usage_page.dart';

void main() {
  testWidgets('Hạn mức mobile hiển thị số đo/cảnh báo và dữ liệu thiếu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = CloudApi(
      'https://fixture.test',
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'state': 'analytics',
            'day_utc': '2026-11-17',
            'generated_at': '2026-11-17T03:00:00Z',
            'cpu_limit_ms': 10,
            'account_storage_limit_bytes': 5000000000,
            'note': 'Số liệu thử có độ trễ.',
            'sources': <String>[],
            'meters': [
              {
                'key': 'write',
                'label': 'Rows written',
                'used': 85000,
                'limit': 100000,
                'percent': 85,
                'level': 'warning',
              },
              {
                'key': 'requests',
                'label': 'Requests Workers',
                'used': null,
                'limit': 100000,
                'percent': null,
                'level': 'unknown',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    )..token = 'fixture';
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CloudUsagePage(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('85.000 / 100.000'), findsOneWidget);
    expect(find.textContaining('Chưa có số đo / 100.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Banner chưa có số đo không bị che và dọn timer khi rời trang', (
    tester,
  ) async {
    final api = CloudApi(
      'https://fixture.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'state': 'not_configured',
            'day_utc': '2026-11-17',
            'meters': <Object>[],
          }),
          200,
        ),
      ),
    )..token = 'fixture';
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CloudUsagePage(api: api, compact: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa có số đo hạn mức'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
