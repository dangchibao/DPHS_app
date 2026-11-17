import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/debt/debt_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalService service;
  setUp(() async {
    service = await salesFixture();
  });
  tearDown(() async {
    await service.db.close();
  });
  test(
    'Đặt cọc rồi thu nhiều lần, retry không nhân đôi và không thu vượt nợ',
    () async {
      final sale = await service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 30000,
        method: 'cash',
        customerName: 'Phụ huynh An',
        phone: '0900000000',
      );
      expect((await service.debts()).single['balance'], 70000);
      final id = await service.collectDebt(
        documentId: sale.id,
        amount: 40000,
        method: 'bank',
        note: 'Thu lần 2',
        commandId: 'payment-command',
      );
      expect(
        await service.collectDebt(
          documentId: sale.id,
          amount: 40000,
          method: 'bank',
          note: 'Thu lần 2',
          commandId: 'payment-command',
        ),
        id,
      );
      expect((await service.debts()).single['balance'], 30000);
      final n = (await service.db.rows('SELECT * FROM payments')).length;
      await expectLater(
        service.collectDebt(
          documentId: sale.id,
          amount: 30001,
          method: 'cash',
          note: 'Thu vượt',
        ),
        throwsStateError,
      );
      expect((await service.db.rows('SELECT * FROM payments')).length, n);
      final jobs = await service.db.rows(
        "SELECT * FROM outbox WHERE entity_type='payment'",
      );
      expect(jobs, hasLength(1));
      final dependencies =
          jsonDecode(jobs.single['dependencies_json'] as String) as List;
      final saleJob = (await service.db.rows(
        "SELECT id FROM outbox WHERE entity_type='sale'",
      )).single['id'];
      expect(dependencies, contains(saleJob));
      await service.collectDebt(
        documentId: sale.id,
        amount: 30000,
        method: 'cash',
        note: 'Tất toán',
      );
      expect(await service.debts(), isEmpty);
      expect(await service.paymentHistory(sale.id), hasLength(3));
      expect(
        (await service.db.rows(
          "SELECT document_code FROM audit_logs WHERE action='PAYMENT_RECEIVE' ORDER BY chain_index DESC LIMIT 1",
        )).single['document_code'],
        sale.code,
      );
    },
  );
}
