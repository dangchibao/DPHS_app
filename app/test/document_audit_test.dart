import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/audit/audit_page.dart';
import 'package:ngoc_thanh_pos/features/audit/document_audit_button.dart';

import 'fixtures.dart';

void main() {
  testWidgets(
    'Lịch sử chứng từ lấy cả sự kiện cũ/phiếu liên quan, không hiện sự kiện khác',
    (tester) async {
      final s = (await tester.runAsync(salesFixture))!;
      addTearDown(() => tester.runAsync(s.db.close));
      final old = LocalService(s.db, clock: () => DateTime.utc(2026, 11, 1))
        ..session = s.session;
      await tester.runAsync(
        () => s.db.transaction(() async {
          await old.audit(
            'TRANSFER_RECEIVE',
            'document',
            'receipt-old',
            reason: 'Nhận chuyển tuần trước',
            changes: {'source_id': 'ck-old'},
          );
          await old.audit(
            'TRANSFER_RECEIVE',
            'document',
            'receipt-other',
            reason: 'Không liên quan',
            changes: {'source_id': 'ck-other'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentAuditButton(service: s, documentId: 'ck-old'),
          ),
        ),
      );
      await tester.tap(find.text('Lịch sử thay đổi'));
      await tester.pumpAndSettle();
      expect(find.text('Lịch sử chứng từ'), findsOneWidget);
      expect(find.textContaining('receipt-old'), findsWidgets);
      expect(find.textContaining('receipt-other'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Cảnh báo đếm đúng sự kiện hủy hiện hành INVOICE_VOID và nút audit ẩn với thu ngân',
    (tester) async {
      final s = (await tester.runAsync(salesFixture))!;
      addTearDown(() => tester.runAsync(s.db.close));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => s.db.transaction(
            () => s.audit(
              'INVOICE_VOID',
              'document',
              'dt-$i',
              reason: 'Hủy fixture',
              changes: {'original_id': 'hd-$i'},
            ),
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AuditPage(service: s)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('5 hóa đơn bị hủy'), findsWidgets);
      s.session = LocalSession(
        userId: 'u1',
        name: 'Thu ngân',
        role: Role.cashier,
        storeId: s.storeId,
        deviceId: s.deviceId,
        expiresAt: DateTime.utc(2027),
      );
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: DocumentAuditButton(service: s, documentId: 'hd-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lịch sử thay đổi'), findsNothing);
    },
  );
}
