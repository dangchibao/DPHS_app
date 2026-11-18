import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/web/web_payroll_page.dart';

void main() {
  testWidgets(
    'Web xem lương mobile hiển thị đúng hoa hồng/thưởng và chặn kỳ sai trước API',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      final api = CloudApi(
        'https://fixture.test',
        client: MockClient((req) async {
          requests++;
          final data = req.url.queryParameters.containsKey('employee_id')
              ? {
                  'rows': [
                    {
                      'employee_name': 'Nhan vien',
                      'period_start': '2026-11-01',
                      'void_reason': null,
                      'needs_reconcile': 0,
                      'created_at': '2026-12-01',
                      'totals_json': jsonEncode({
                        'base_pay': 200000,
                        'commission_pay': 12345,
                        'bonus_pay': 67890,
                        'total_pay': 280235,
                      }),
                    },
                  ],
                  'cursor': '',
                  'has_more': false,
                }
              : {
                  'employees': [
                    {'id': 'u1', 'display_name': 'Nhan vien', 'active': 1},
                  ],
                  'cursor': 'u1',
                  'has_more': false,
                };
          return http.Response(jsonEncode(data), 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WebPayrollPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem kỳ lương'));
      await tester.pumpAndSettle();
      expect(find.textContaining('12.345'), findsOneWidget);
      expect(find.textContaining('67.890'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.tap(find.text('Xem kỳ lương'));
      await tester.pump();
      expect(requests, 2);
      expect(find.text('Kỳ lương dạng YYYY-MM.'), findsOneWidget);
    },
  );
}
