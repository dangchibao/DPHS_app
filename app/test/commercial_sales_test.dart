import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/pricing/commercial_rule.dart';
import 'package:ngoc_thanh_pos/features/pricing/commercial_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Bảng giá đại lý, voucher, đặt cọc, snapshot và retry giữ đúng tiền',
    () async {
      final s = await salesFixture();
      try {
        final dealer = await s.saveDealer(
          name: 'Đại lý mẫu',
          phone: '0900000000',
        );
        final list = await s.saveCommercialRule(
          name: 'Giá đại lý',
          kind: 'price_list',
          config: {
            ...CommercialRule.defaults(),
            'discount_type': 'none',
            'customer_kind': 'dealer',
            'prices': {'v1': 80000},
          },
        );
        final promo = await s.saveCommercialRule(
          name: 'Đầu năm',
          kind: 'promotion',
          config: {
            ...CommercialRule.defaults(),
            'value': 1000,
            'discount_type': 'percent',
            'voucher': 'DAUNAM',
            'allow_price_list': true,
          },
        );
        final sale = await s.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 20000,
          method: 'cash',
          customerId: dealer,
          priceListId: list,
          promotionId: promo,
          voucher: 'daunam',
          commandId: 'sale-commercial',
          expectedTotal: 72000,
        );
        expect(sale.total, 72000);
        expect(
          (await s.db.rows('SELECT amount FROM receivable_entries'))
              .single['amount'],
          52000,
        );
        final snapshot = jsonDecode(
          (await s.db.rows('SELECT metadata_json FROM documents'))
                  .single['metadata_json']
              as String,
        ) as Map;
        expect(snapshot['price_list_name'], 'Giá đại lý');
        expect(snapshot['promotion_discount'], 8000);
        expect(
          (await s.db.rows('SELECT unit_price,discount FROM invoice_lines'))
              .single,
          {'unit_price': 80000, 'discount': 8000},
        );
        final saleJob = (await s.db.rows(
          "SELECT dependencies_json FROM outbox WHERE entity_type='sale'",
        )).single;
        final deps = jsonDecode(saleJob['dependencies_json'] as String) as List;
        final ruleJobs = await s.db.rows(
          "SELECT id FROM outbox WHERE entity_type IN ('commercial','dealer')",
        );
        expect(deps, containsAll(ruleJobs.map((r) => r['id'])));
        await s.saveCommercialRule(
          id: promo,
          name: 'Đã dừng',
          kind: 'promotion',
          active: false,
          config: {...CommercialRule.defaults(), 'value': 1000},
        );
        final retry = await s.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 20000,
          method: 'cash',
          customerId: dealer,
          priceListId: list,
          promotionId: promo,
          voucher: 'daunam',
          commandId: 'sale-commercial',
          expectedTotal: 72000,
        );
        expect(retry.code, sale.code);
        expect((await s.db.rows('SELECT * FROM documents')).length, 1);
      } finally {
        await s.db.close();
      }
    },
  );
  test(
    'Sai đối tượng/khuyến mãi/manual/tổng dự kiến rollback kho và counter',
    () async {
      final s = await salesFixture();
      try {
        final list = await s.saveCommercialRule(
          name: 'Đại lý',
          kind: 'price_list',
          config: {
            ...CommercialRule.defaults(),
            'discount_type': 'none',
            'customer_kind': 'dealer',
            'prices': {'v1': 50000},
          },
        );
        final promo = await s.saveCommercialRule(
          name: 'Ưu đãi',
          kind: 'promotion',
          config: {...CommercialRule.defaults(), 'value': 1000},
        );
        await expectLater(
          s.sell(
            items: [const CartItem('v1', 1)],
            discount: 0,
            received: 100000,
            method: 'cash',
            priceListId: list,
          ),
          throwsStateError,
        );
        await expectLater(
          s.sell(
            items: [const CartItem('v1', 1)],
            discount: 1,
            received: 100000,
            method: 'cash',
            promotionId: promo,
          ),
          throwsStateError,
        );
        await expectLater(
          s.sell(
            items: [const CartItem('v1', 1)],
            discount: 0,
            received: 100000,
            method: 'cash',
            expectedTotal: 99999,
          ),
          throwsStateError,
        );
        expect(await s.db.rows('SELECT * FROM documents'), isEmpty);
        expect(await s.db.rows('SELECT * FROM document_counters'), isEmpty);
        expect(
          (await s.db.rows('SELECT quantity FROM stock_balances'))
              .single['quantity'],
          10,
        );
        final parentPromo = await s.saveCommercialRule(
          name: 'Phụ huynh',
          kind: 'promotion',
          config: {
            ...CommercialRule.defaults(),
            'value': 1000,
            'customer_kind': 'parent',
          },
        );
        final parentSale = await s.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 99000,
          method: 'cash',
          promotionId: parentPromo,
          expectedTotal: 99000,
        );
        expect(parentSale.total, 99000);
        s.session = LocalSession(
          userId: 'u1',
          name: 'Thu ngân',
          role: Role.cashier,
          storeId: s.storeId,
          deviceId: s.deviceId,
          expiresAt: DateTime.utc(2027),
        );
        await expectLater(
          s.saveCommercialRule(
            name: 'Không quyền',
            kind: 'promotion',
            config: {...CommercialRule.defaults(), 'value': 1},
          ),
          throwsStateError,
        );
      } finally {
        await s.db.close();
      }
    },
  );
}
