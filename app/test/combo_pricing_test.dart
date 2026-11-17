import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/pos/pricing.dart';

void main() {
  final vectors = jsonDecode(
    File('../docs/test-vectors/combo-pricing.json').readAsStringSync(),
  ) as List;
  for (final raw in vectors) {
    final vector = Map<String, Object?>.from(raw as Map);
    test('Tính giá dùng chung: ${vector['name']}', () {
      final items = (vector['items'] as List).map((raw) {
        final r = Map<String, Object?>.from(raw as Map);
        return PricedItem(
          id: r['id'] as String,
          productId: r['product_id'] as String,
          price: r['price'] as int,
          quantity: r['quantity'] as int,
        );
      }).toList();
      final groups = (vector['combos'] as List)
          .map(
            (v) => ComboSelection.fromJson(Map<String, Object?>.from(v as Map)),
          )
          .toList();
      final result = priceCart(items, groups);
      expect({
        'regular_subtotal': result.regularSubtotal,
        'subtotal': result.subtotal,
        'rounding_discount': result.roundingDiscount,
        'amount': result.amount,
        'lines': {
          for (final e in result.lines.entries)
            e.key: [
              e.value.amount,
              e.value.unitPrice,
              e.value.roundingDiscount,
            ],
        },
      }, vector['expected']);
    });
  }
  test('Combo không lấy hai lần lượng hàng không có hoặc sai sản phẩm', () {
    const rule = ComboDefinition(
      id: 'set',
      version: 'v1',
      name: 'Bộ',
      price: 1,
      parts: [ComboPart('shirt', 2)],
    );
    expect(
      () => priceCart(
        [
          const PricedItem(
            id: 'a',
            productId: 'shirt',
            price: 100,
            quantity: 1,
          ),
        ],
        [
          const ComboSelection(rule: rule, picks: ['a']),
        ],
      ),
      throwsStateError,
    );
    expect(
      () => priceCart(
        [const PricedItem(id: 'a', productId: 'hat', price: 100, quantity: 2)],
        [
          const ComboSelection(rule: rule, picks: ['a']),
        ],
      ),
      throwsStateError,
    );
  });
}
