import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/pricing/commercial_rule.dart';
import 'package:ngoc_thanh_pos/features/pricing/commercial_page.dart';
import 'package:ngoc_thanh_pos/features/pos/pricing.dart';

void main() {
  final vectors = jsonDecode(
    File('../docs/test-vectors/commercial-pricing.json').readAsStringSync(),
  ) as List;
  for (final raw in vectors) {
    final v = Map<String, Object?>.from(raw as Map);
    test(v['name'] as String, () {
      int run() {
        final rule = CommercialRule(
          id: 'r1',
          version: 'v',
          name: 'Ưu đãi',
          kind: 'promotion',
          config: {
            ...CommercialRule.defaults(),
            'value': 1000,
            ...Map<String, Object?>.from(v['config'] as Map),
          },
        );
        rule.requireEligible(
          school: v['school'] as String?,
          customerKind: v['customerKind'] as String?,
          issuedAt: DateTime.utc(2026, 11, 15),
          quantity: v['quantity'] as int? ?? 1,
          amount: v['amount'] as int,
          combos: v['combos'] == true,
          voucher: v['voucher'] as String? ?? '',
        );
        return rule.discount(
          v['amount'] as int,
          manual: v['manual'] as int? ?? 0,
          hasPriceList: v['priceList'] == true,
        );
      }

      if (v['reject'] == true) {
        expect(run, throwsStateError);
      } else {
        expect(run(), v['expected']);
      }
    });
  }
  test('Giá riêng theo biến thể, phần trăm nhập chính xác không float', () {
    final rule = CommercialRule(
      id: 'r',
      version: 'v',
      name: 'Giá trường',
      kind: 'price_list',
      config: {
        ...CommercialRule.defaults(),
        'discount_type': 'none',
        'prices': {'v1': 80000},
      },
    );
    expect(
      applyPriceList(rule, [
        const PricedItem(id: 'v1', productId: 'p1', price: 100000, quantity: 1),
        const PricedItem(id: 'v2', productId: 'p1', price: 120000, quantity: 2),
      ]).map((i) => i.price),
      [80000, 120000],
    );
    expect(percentBasisPoints('12,50'), 1250);
    expect(percentBasisPoints('0.01'), 1);
    expect(() => percentBasisPoints('100.01'), throwsArgumentError);
  });
}
