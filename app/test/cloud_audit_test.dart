import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/audit/cloud_audit_page.dart';

void main() {
  testWidgets(
    'Nhật ký cloud mobile lọc cửa hàng, xem nội dung và chuyển cursor rỗng',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reads = 0;
      String? scope;
      final api = CloudApi(
        'https://fixture.test',
        client: MockClient((req) async {
          if (req.url.path == '/audit/options') {
            return http.Response(
              jsonEncode({
                'stores': [
                  {'id': 's1', 'code': 'CN01', 'name': 'Cửa hàng 1'},
                  {'id': 's2', 'code': 'CN02', 'name': 'Cửa hàng 2'},
                ],
                'can_all_stores': true,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          reads++;
          scope = req.url.queryParameters['store'];
          if (reads == 1) {
            return http.Response(
              jsonEncode({
                'rows': [],
                'cursor': '["s1","t","id"]',
                'has_more': true,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(req.url.queryParameters['cursor'], '["s1","t","id"]');
          return http.Response(
            jsonEncode({
              'rows': [
                {
                  'id': 'a1',
                  'action': 'STOCK_ADJUST',
                  'entity_id': 'v1',
                  'store_id': 's1',
                  'client_time': '2026-11-17T00:00:00Z',
                  'user_id': 'u1',
                  'device_id': 'd1',
                  'reason': 'Kiểm kho thử',
                  'changes_json': '{"quantity":2}',
                },
              ],
              'cursor': 'end',
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudAuditPage(api: api, storeId: 's1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        scope,
        's1',
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Trang tiếp'));
      await tester.tap(find.text('Trang tiếp'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Điều chỉnh tồn kho'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Điều chỉnh tồn kho'));
      await tester.tap(find.textContaining('Điều chỉnh tồn kho'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kiểm kho thử'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(reads, 2);
    },
  );
}
