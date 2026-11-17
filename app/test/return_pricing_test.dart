import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/returns/return_pricing.dart';

void main() {
  final vectors = jsonDecode(
    File('../docs/test-vectors/return-settlement.json').readAsStringSync(),
  ) as List;
  for (final raw in vectors) {
    final v = raw as Map;
    test(v['name'] as String, () {
      ReturnSettlement run() => settleReturn(
        v['balance'] as int,
        v['returned'] as int,
        v['replacement'] as int,
        v['received'] as int,
      );
      if (v['reject'] == true) {
        expect(run, throwsArgumentError);
      } else {
        final r = run();
        expect(
          [r.offset, r.cashDue, r.refund, r.newDebt],
          [v['offset'], v['due'], v['refund'], v['debt']],
        );
      }
    });
  }
  test('Trả phần lẻ cộng đúng net, đổi size giữ nguyên giá sau ưu đãi', () {
    expect(
      [for (var i = 0; i < 3; i++) returnCredit(100001, 3, i, 1)],
      [33333, 33334, 33334],
    );
    expect(() => returnCredit(100001, 3, 2, 2), throwsStateError);
    final plan = priceReplacements(
      [const ReplacementSelection('v2', 3, sourceLineId: 'old')],
      {'old': ReturnedItem(productId: 'p1', quantity: 3, credit: 100001)},
      {'v2': ReplacementVariant('p1', 150000)},
    );
    expect(plan['v2']!.unitPrice, 33334);
    expect(plan['v2']!.discount, 1);
    expect(plan['v2']!.amount, 100001);
    expect(
      () => priceReplacements(
        [const ReplacementSelection('v2', 1, sourceLineId: 'old')],
        {'old': ReturnedItem(productId: 'p1', quantity: 1, credit: 100000)},
        {'v2': ReplacementVariant('p2', 50000)},
      ),
      throwsStateError,
    );
  });
}
