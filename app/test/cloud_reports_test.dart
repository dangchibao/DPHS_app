import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/reports/cloud_reports.dart';
import 'package:ngoc_thanh_pos/features/reports/report_service.dart';
import 'package:ngoc_thanh_pos/features/reports/online_reports_page.dart';

Map<String, Object?> metric(
  String revenue,
  String cost,
  String qty,
  String paid, {
  String refund = '0',
}) => {
  'revenue': revenue,
  'cost': cost,
  'quantity': qty,
  'payment_in': paid,
  'payment_out': refund,
  'invoices': '1',
  'p|p1|revenue': revenue,
  'p|p1|cost': cost,
  'p|p1|quantity': qty,
  's|4D|revenue': revenue,
  's|4D|cost': cost,
  's|4D|quantity': qty,
  'e|u1|revenue': revenue,
  'e|u1|cost': cost,
  'e|u1|quantity': qty,
  'label|p|p1': 'Áo sơ mi',
  'label|s|4D': 'M',
  'label|e|u1': 'Nhân viên',
};
Map<String, Object?> daily(String store, Map<String, Object?> values) => {
  'store_id': store,
  'day': '2026-11-15',
  'school_year': '2026–2027',
  'school_id': '',
  'metrics': values,
};
CloudApi fixtureApi({
  bool repeated = false,
  void Function(http.Request)? inspect,
}) {
  return CloudApi(
    'https://api.test',
    client: MockClient((request) async {
      inspect?.call(request);
      final all = request.url.queryParameters['store'] == 'all';
      final stores = [
        {'id': 's1', 'code': 'NT-CN01', 'name': 'CN01'},
        if (all) {'id': 's2', 'code': 'NT-CN02', 'name': 'CN02'},
      ];
      Object result;
      switch (request.url.path) {
        case '/reports/options':
          result = {
            'stores': [
              {'id': 's1', 'code': 'NT-CN01', 'name': 'CN01'},
            ],
            'schools': [],
            'can_all_stores': true,
          };
        case '/reports/daily':
          if (repeated) {
            result = {
              'rows': [],
              'next_cursor': 'repeat',
              'feed_cursor': '41',
              'stores': stores,
            };
          } else if (request.url.queryParameters['cursor'] != null) {
            result = {
              'rows': [
                daily('s2', metric('50', '20', '1', '50', refund: '10')),
              ],
              'next_cursor': null,
              'feed_cursor': '42',
              'stores': stores,
            };
          } else {
            result = {
              'rows': [daily('s1', metric('100', '10', '1', '100'))],
              'next_cursor': all ? 'page2' : null,
              'feed_cursor': '41',
              'stores': stores,
            };
          }
        case '/reports/refresh':
          result = {
            'rows': [daily('s1', metric('200', '80', '2', '150'))],
            'generated_at': '2026-11-17T00:00:00.000Z',
          };
        case '/reports/details':
          final kind = request.url.queryParameters['kind'];
          result = {
            'rows': kind == 'stock'
                ? [
                    {
                      'store_id': 's1',
                      'id': 'v1',
                      'name': 'Áo sơ mi',
                      'size': 'M',
                      'color': 'Trắng',
                      'quantity': '10',
                      'reserved': '2',
                      'unit_cost': '9007199254740991',
                    },
                  ]
                : kind == 'debts'
                ? [
                    {
                      'store_id': 's1',
                      'id': 'hd1',
                      'code': 'HD-test',
                      'customer_name': 'Khách',
                      'amount': '50000',
                      'due_date': '2026-11-16',
                    },
                  ]
                : <Object?>[],
            'next_cursor': null,
            'generated_at': '2026-11-17T00:00:00.000Z',
          };
        case '/reports/rebuild':
          result = {'processed': 0, 'has_more': false};
        default:
          throw StateError('Unexpected ${request.url}');
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  )..token = 'interactive';
}

void main() {
  test(
    'Cloud merge snapshot thay vì cộng trùng, giữ mốc đầu và số VND lớn',
    () async {
      final api = fixtureApi(
        inspect: (request) {
          if (request.url.path == '/reports/refresh') {
            expect(request.url.queryParameters['since'], '41');
          }
          expect(request.headers['X-Client-Schema'], '30');
        },
      );
      addTearDown(api.close);
      final report = await CloudReports(api)
          .read(ReportRange('2026-11-01', '2026-11-30'), 'all');
      expect(report.totals['revenue'], BigInt.from(250));
      expect(report.totals['cost'], BigInt.from(100));
      expect(report.totals['gross_profit'], BigInt.from(150));
      expect(report.totals['cashflow'], BigInt.from(190));
      expect(report.totals['debt'], BigInt.from(50000));
      expect(report.totals['overdue'], BigInt.from(50000));
      expect(
        report.tables['Sản phẩm · lãi gộp']!.rows.single[2],
        BigInt.from(250),
      );
      expect(
        report.tables['Tồn kho hiện tại']!.rows.single[7],
        BigInt.parse('90071992547409910'),
      );
      expect(report.storeLabel, 'Toàn hệ thống · 2 cửa hàng');
      expect(report.tables, contains('Công nợ hiện tại'));
    },
  );
  test(
    'Không đăng nhập, hủy trang hoặc cursor lặp không trả báo cáo thiếu',
    () async {
      final api = fixtureApi();
      addTearDown(api.close);
      api.token = null;
      await expectLater(
        CloudReports(api).read(ReportRange('2026-11-01', '2026-11-30'), 's1'),
        throwsStateError,
      );
      api.token = 'interactive';
      await expectLater(
        CloudReports(api).read(
          ReportRange('2026-11-01', '2026-11-30'),
          's1',
          isCancelled: () => true,
        ),
        throwsStateError,
      );
      final broken = fixtureApi(repeated: true);
      addTearDown(broken.close);
      await expectLater(
        CloudReports(broken)
            .read(ReportRange('2026-11-01', '2026-11-30'), 's1'),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'Báo cáo online mobile hiển thị số thật, chọn scope và xuất qua callback',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = fixtureApi();
      addTearDown(api.close);
      var exported = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnlineReportsPage(
              api: api,
              storeId: 's1',
              clock: () => DateTime.utc(2026, 11, 17),
              exportAction: (name, table, pdf) async {
                exported++;
                expect(name, contains('NT-CN01'));
                expect(pdf, isFalse);
                expect(table.headers.first, 'Ngày');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dashboard cloud · nhiều cửa hàng'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Doanh thu thuần'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Doanh thu thuần'),
        findsWidgets,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join('\n'),
      );
      expect(find.text('200 đ'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Xuất Excel'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Xuất Excel'));
      await tester.pumpAndSettle();
      expect(exported, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
