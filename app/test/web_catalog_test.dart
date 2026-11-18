import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/web/web_catalog_page.dart';

void main() {
  testWidgets(
    'Web tạo sản phẩm trên mobile, retry giữ cùng UUID/payload và không ghi ledger',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final posts = <Map<String, dynamic>>[];
      final api = CloudApi(
        'https://fixture.test',
        client: MockClient((req) async {
          if (req.method == 'GET') {
            return http.Response(
              '{"rows":[],"cursor":"","has_more":false}',
              200,
            );
          }
          posts.add(jsonDecode(req.body) as Map<String, dynamic>);
          if (posts.length == 1) {
            return http.Response('{"error":"fixture unavailable"}', 503);
          }
          return http.Response(
            jsonEncode({
              'acknowledged': [posts.last['id']],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebCatalogPage(
              api: api,
              storeId: 's1',
              deviceId: 'web',
              userId: 'u1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm sản phẩm'));
      await tester.pumpAndSettle();
      for (final pair in [
        ('Tên sản phẩm', 'Áo thử'),
        ('Size', 'M'),
        ('Màu', 'Trắng'),
        ('SKU', 'SKU-NEW'),
        ('Lý do thay đổi', 'Tạo sản phẩm thử'),
      ]) {
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == pair.$1,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, pair.$2);
      }
      await tester.tap(find.text('Lưu online'));
      await tester.pumpAndSettle();
      expect(posts.length, 1);
      await tester.tap(find.text('Lưu online'));
      await tester.pumpAndSettle();
      expect(posts.length, 2);
      expect(posts[0], posts[1]);
      expect((posts[0]['records'] as List).map((dynamic r) => r['table']), [
        'products',
        'product_variants',
        'stock_threshold_rules',
      ]);
      expect(find.text('Lưu online'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
