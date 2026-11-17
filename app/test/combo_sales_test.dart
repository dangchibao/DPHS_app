import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/catalog/combo_service.dart';
import 'package:ngoc_thanh_pos/features/pos/pricing.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalService service;
  setUp(() async {
    service = await salesFixture();
    await service.db.execute(
      "INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES ('v2','p1','SKU-L','L','Xanh','cái',45000,100000,'2026-11-15')",
    );
    await service.adjustStock('v2', 5, 'Nhập size L');
  });
  tearDown(() async {
    await service.db.close();
  });
  Future<ComboSelection> combo() async {
    await service.saveCombo(
      name: 'Hai áo hai size',
      price: 150001,
      parts: [const ComboPart('p1', 1), const ComboPart('p1', 1)],
    );
    final rule = comboFromRow((await service.comboRules()).single);
    return ComboSelection(rule: rule, picks: ['v1', 'v2']);
  }

  test('Combo trừ đúng size/màu, phân bổ tiền nguyên, snapshot và retry đúng một lần', () async {
    final group = await combo();
    final sale = await service.sell(
      items: [const CartItem('v1', 1), const CartItem('v2', 1)],
      discount: 10000,
      received: 200000,
      method: 'cash',
      combos: [group],
      commandId: 'combo-sale',
    );
    expect(sale.total, 140001);
    expect(sale.change, 59999);
    final balances = await service.db.rows(
      'SELECT variant_id,quantity FROM stock_balances ORDER BY variant_id',
    );
    expect(balances, [
      {'variant_id': 'v1', 'quantity': 9},
      {'variant_id': 'v2', 'quantity': 4},
    ]);
    final lines = await service.db.rows(
      'SELECT quantity,unit_price,discount FROM invoice_lines',
    );
    expect(
      lines.fold(
        0,
        (int total, row) =>
            total +
            (row['quantity'] as int) * (row['unit_price'] as int) -
            (row['discount'] as int),
      ),
      140001,
    );
    final job = (await service.db.rows(
      "SELECT dependencies_json FROM outbox WHERE entity_type='sale'",
    )).single;
    final ruleJob = (await service.db.rows(
      "SELECT id FROM outbox WHERE entity_type='combo'",
    )).single['id'];
    expect(jsonDecode(job['dependencies_json'] as String), contains(ruleJob));
    await service.saveCombo(
      id: group.rule.id,
      name: 'Tên combo mới',
      price: 190000,
      parts: group.rule.parts,
    );
    final metadata = jsonDecode(
      (await service.db.rows('SELECT metadata_json FROM documents'))
              .single['metadata_json']
          as String,
    ) as Map;
    expect((metadata['combo_snapshots'] as List).single['price'], 150001);
    final replay = await service.sell(
      items: [const CartItem('v1', 1), const CartItem('v2', 1)],
      discount: 10000,
      received: 200000,
      method: 'cash',
      combos: [group],
      commandId: 'combo-sale',
    );
    expect(replay.id, sale.id);
    expect(await service.db.rows('SELECT * FROM documents'), hasLength(1));
    await expectLater(
      service.sell(
        items: [const CartItem('v1', 1), const CartItem('v2', 1)],
        discount: 0,
        received: 150001,
        method: 'cash',
        combos: [group],
      ),
      throwsStateError,
    );
  });
  test('Giữ lại đơn combo cập nhật cùng draft, đơn đã thanh toán không được phát hành lại', () async {
    final group = await combo();
    final items = [const CartItem('v1', 1), const CartItem('v2', 1)];
    await service.holdCart(items, 'Đơn tạm combo', combos: [group]);
    final draft = (await service.db.rows('SELECT * FROM held_carts')).single;
    expect(
      (jsonDecode(draft['payload'] as String)['combos'] as List),
      hasLength(1),
    );
    await service.holdCart(
      items,
      'Cập nhật đơn tạm',
      combos: [group],
      existingId: draft['id'] as String,
    );
    expect(await service.db.rows('SELECT * FROM held_carts'), hasLength(1));
    final sale = await service.sell(
      items: items,
      discount: 0,
      received: 150001,
      method: 'cash',
      combos: [group],
      heldCartId: draft['id'] as String,
      commandId: 'held-sale',
    );
    expect(await service.db.rows('SELECT * FROM held_carts'), isEmpty);
    expect(
      (await service.sell(
        items: items,
        discount: 0,
        received: 150001,
        method: 'cash',
        combos: [group],
        heldCartId: draft['id'] as String,
        commandId: 'held-sale',
      )).id,
      sale.id,
    );
    await expectLater(
      service.sell(
        items: items,
        discount: 0,
        received: 150001,
        method: 'cash',
        combos: [group],
        heldCartId: draft['id'] as String,
      ),
      throwsStateError,
    );
    expect(await service.db.rows('SELECT * FROM documents'), hasLength(1));
  });
  test('Không cấp giá combo khi thiếu món; không tin giá giả trong dữ liệu chọn ở client', () async {
    final group = await combo();
    await expectLater(
      service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 150001,
        method: 'cash',
        combos: [group],
      ),
      throwsStateError,
    );
    final forged = ComboSelection(
      rule: ComboDefinition(
        id: group.rule.id,
        version: group.rule.version,
        name: 'Giả giá',
        price: 1,
        parts: group.rule.parts,
      ),
      picks: group.picks,
    );
    final sale = await service.sell(
      items: [const CartItem('v1', 1), const CartItem('v2', 1)],
      discount: 0,
      received: 150001,
      method: 'cash',
      combos: [forged],
    );
    expect(sale.total, 150001);
  });
}
