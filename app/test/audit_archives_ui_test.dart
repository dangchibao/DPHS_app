import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/audit/audit_archives_page.dart';

Future<void> io(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'Lưu trữ cần file verified và xác nhận cuối; lỗi upload giữ lô để tiếp tục, viewer không có quyền chốt',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = utf8.encode('{"fixture":"source"}');
      Map<String, dynamic>? manifest;
      var uploads = 0, commits = 0;
      http.Response response(Object data, [int status = 200]) => http.Response(
        jsonEncode(data),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final api = CloudApi(
        'https://fixture.test',
        client: MockClient((req) async {
          if (req.method == 'GET') {
            return response({
              'rows': [?manifest],
              'cursor': '',
              'has_more': false,
              'devices': [
                {'id': 'd1', 'code': 'A2', 'name': 'Máy thử'},
              ],
              'device_cursor': 'A2',
              'more_devices': false,
              'enabled': true,
              'retention_days': 90,
            });
          }
          if (req.method == 'PUT') {
            uploads++;
            expect(
              utf8.decode(GZipDecoder().decodeBytes(req.bodyBytes)),
              utf8.decode(source),
            );
            if (uploads == 1) {
              return response({'error': 'Upload thử bị lỗi'}, 503);
            }
            manifest!['status'] = 'verified';
            return response({'id': manifest!['id'], 'verified': true});
          }
          final data = jsonDecode(req.body) as Map;
          if (data['action'] == 'prepare') {
            manifest ??= {
              'id': data['id'],
              'store_id': 's1',
              'device_id': 'd1',
              'direction': 1,
              'first_index': 1,
              'last_index': 2,
              'record_count': 2,
              'status': 'prepared',
              'source_bytes': source.length,
              'source_hash': sha256.convert(source).toString(),
              'created_at': '2026-11-17',
            };
            return response({
              'manifest': manifest,
              'source_base64': base64Encode(source),
            });
          }
          expect(data['action'], 'commit');
          expect(data['confirmed'], true);
          commits++;
          manifest!['status'] = 'committed';
          return response({'id': manifest!['id'], 'committed': true});
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditArchivesPage(api: api, storeId: 's1', canArchive: true),
          ),
        ),
      );
      await io(tester);
      await tester.tap(find.text('Chuẩn bị lô log cũ'));
      await io(tester);
      expect(commits, 0);
      expect(uploads, 1);
      expect(find.textContaining('Upload thử bị lỗi'), findsOneWidget);
      await tester.ensureVisible(find.text('Tiếp tục / hoàn tất'));
      await tester.tap(find.text('Tiếp tục / hoàn tất'));
      await io(tester);
      expect(find.text('Lưu trữ log cũ đã xác minh'), findsOneWidget);
      expect(commits, 0);
      expect(uploads, 2);
      await tester.tap(find.text('Để sau'));
      await io(tester);
      expect(commits, 0);
      await tester.ensureVisible(find.text('Tiếp tục / hoàn tất'));
      await tester.tap(find.text('Tiếp tục / hoàn tất'));
      await io(tester);
      await tester.tap(find.text('Hoàn tất lưu trữ'));
      await io(tester);
      expect(commits, 1);
      expect(uploads, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditArchivesPage(
              key: const ValueKey('viewer'),
              api: api,
              storeId: 's1',
            ),
          ),
        ),
      );
      await io(tester);
      expect(find.text('Chuẩn bị lô log cũ'), findsNothing);
      expect(find.text('Tiếp tục / hoàn tất'), findsNothing);
      expect(find.text('Tải file gzip'), findsOneWidget);
    },
  );
}
