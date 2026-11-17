import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/sizes/size_rule.dart';
import 'package:ngoc_thanh_pos/features/sizes/size_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final vectors = jsonDecode(
    File('../docs/test-vectors/size-suggestions.json').readAsStringSync(),
  ) as Map;
  final rule = SizeRule.parse(jsonEncode(vectors['rows']));
  for (final c in vectors['cases'] as List) {
    test(
      c['name'] as String,
      () => expect(
        rule.suggest(c['height'] as int, c['weight'] as int),
        c['expected'],
      ),
    );
  }
  test('Chặn khoảng đảo, số lẻ mm/gram, cột lạ và size lặp', () {
    for (final data in [
      <Map<String, Object?>>[],
      [
        {...rule.rows.first, 'height_min': 1500},
      ],
      [
        {...rule.rows.first, 'weight_min': 18.5},
      ],
      [
        {...rule.rows.first, 'height': 1300},
      ],
      [rule.rows.first, rule.rows.first],
    ]) {
      expect(() => SizeRule(data), throwsArgumentError);
    }
    expect(() => rule.suggest(0, 30000), throwsArgumentError);
  });
  test(
    'Lưu cấu hình/audit/outbox và quyền sửa, không đổi giá hay kho',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      await s.saveSizeRule(name: 'Bảng áo', productId: 'p1', rule: rule);
      final saved = (await s.sizeRules()).single;
      expect(saved['product_name'], 'Áo sơ mi');
      expect(saved['lww_key'], contains('|device-a2|'));
      expect(
        (await s.db.rows('SELECT quantity FROM stock_balances'))
            .single['quantity'],
        10,
      );
      expect(
        (await s.db.rows("SELECT id FROM outbox WHERE entity_type='size_rule'"))
            .length,
        1,
      );
      s.session = LocalSession(
        userId: 'u1',
        name: 'Thu ngân',
        role: Role.cashier,
        storeId: s.storeId,
        deviceId: s.deviceId,
        expiresAt: DateTime.utc(2027),
      );
      expect(await s.sizeRules(), hasLength(1));
      await expectLater(
        s.saveSizeRule(name: 'Sửa trái quyền', rule: rule),
        throwsStateError,
      );
    },
  );
}
