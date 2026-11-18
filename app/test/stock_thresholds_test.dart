import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/catalog/catalog_service.dart';

import 'fixtures.dart';

Future<void> save(LocalService s, int threshold) => s.saveVariant(
  existing: {'id': 'v1', 'product_id': 'p1'},
  name: 'Áo',
  category: 'Áo sơ mi',
  gender: 'Unisex',
  level: 'Tiểu học',
  year: '2026–2027',
  size: 'M',
  color: 'Trắng',
  unit: 'cái',
  sku: 'SKU1',
  barcode: '',
  price: 100000,
  cost: 50000,
  threshold: threshold,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Lưu ngưỡng cùng catalog, audit và outbox; giữ giá và không gửi lại rule cũ', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    await s.db.execute(
      "INSERT INTO store_variant_settings VALUES('store-cn01','v1',95000,3)",
    );
    await save(s, 7);
    expect(
      (await s.db.rows(
        'SELECT low_stock_threshold,price_override FROM store_variant_settings',
      )).single,
      {'low_stock_threshold': 7, 'price_override': 95000},
    );
    final rules = await s.db.rows('SELECT * FROM stock_threshold_rules');
    expect(rules.length, 1);
    final queue = await s.db.rows(
      "SELECT payload FROM outbox WHERE entity_type='catalog'",
    );
    final data = jsonDecode(queue.single['payload'] as String) as List<dynamic>;
    expect(
      data.where((dynamic r) => r['table'] == 'stock_threshold_rules').length,
      1,
    );
    await save(s, 7);
    expect((await s.db.rows('SELECT id FROM stock_threshold_rules')).length, 1);
    final queues = await s.db.rows(
      "SELECT payload FROM outbox WHERE entity_type='catalog' ORDER BY rowid",
    );
    expect(
      (jsonDecode(queues.last['payload'] as String) as List).where(
        (dynamic r) => r['table'] == 'stock_threshold_rules',
      ),
      isEmpty,
    );
  });
  test(
    'Audit lỗi rollback ngưỡng và chỉnh sản phẩm; từ chối số vượt miền an toàn',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      await s.db.execute(
        "CREATE TRIGGER fail_catalog BEFORE INSERT ON audit_logs WHEN NEW.action='PRODUCT_UPDATE' BEGIN SELECT RAISE(ABORT,'fixture'); END",
      );
      await expectLater(save(s, 9), throwsA(anything));
      expect(await s.db.rows('SELECT * FROM stock_threshold_rules'), isEmpty);
      expect(await s.db.rows('SELECT * FROM store_variant_settings'), isEmpty);
      await expectLater(save(s, 9007199254740992), throwsArgumentError);
    },
  );
}
