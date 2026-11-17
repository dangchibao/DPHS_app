import 'dart:convert';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../schools/school_service.dart';
import '../pos/pricing.dart';
import 'commercial_rule.dart';

class CommercialQuote {
  CommercialQuote(
    this.price,
    this.promotionDiscount,
    this.priceList,
    this.promotion,
  );
  final CartPrice price;
  final int promotionDiscount;
  final CommercialRule? priceList, promotion;
}

extension CommercialService on LocalService {
  Future<List<Map<String, Object?>>> commercialRules({
    bool activeOnly = false,
  }) {
    requireSchoolRead();
    return db.rows(
      'SELECT * FROM commercial_rules WHERE store_id=? ${activeOnly ? 'AND active=1' : ''} ORDER BY kind,name',
      [storeId],
    );
  }

  Future<String> saveCommercialRule({
    String? id,
    required String name,
    required String kind,
    required Map<String, Object?> config,
    bool active = true,
  }) async {
    require(Permission.catalog);
    final target = id ?? uuid.v7();
    return db.transaction(() async {
      final before = id == null
          ? <Map<String, Object?>>[]
          : await db.rows(
              'SELECT * FROM commercial_rules WHERE store_id=? AND id=?',
              [storeId, id],
            );
      if (id != null && before.isEmpty) {
        throw StateError('Không tìm thấy quy tắc giá.');
      }
      final rule = CommercialRule(
        id: target,
        version: '$now|$deviceId|${uuid.v7()}',
        name: name.trim(),
        kind: kind,
        config: config,
      );
      if (config['school_id'] != null &&
          (await db.rows('SELECT id FROM schools WHERE store_id=? AND id=?', [
            storeId,
            config['school_id'],
          ])).isEmpty) {
        throw StateError('Trường không thuộc cửa hàng.');
      }
      for (final variant in rule.prices.keys) {
        if ((await db.rows('SELECT id FROM product_variants WHERE id=?', [
          variant,
        ])).isEmpty) {
          throw StateError('Biến thể không tồn tại.');
        }
      }
      await db.execute(
        'INSERT INTO commercial_rules VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,kind=excluded.kind,config_json=excluded.config_json,active=excluded.active,updated_at=excluded.updated_at,lww_key=excluded.lww_key',
        [
          target,
          storeId,
          rule.name,
          kind,
          jsonEncode(config),
          active ? 1 : 0,
          now,
          rule.version,
        ],
      );
      await audit(
        'COMMERCIAL_SAVE',
        'commercial_rule',
        target,
        reason: 'Cập nhật bảng giá / khuyến mãi',
        severity: 'sensitive',
        changes: {
          'before': before.firstOrNull,
          'after': {
            'name': rule.name,
            'kind': kind,
            'config': config,
            'active': active,
          },
        },
      );
      await enqueue('commercial', {'id': target}, 3);
      return target;
    });
  }

  Future<CommercialQuote> commercialQuote({
    required List<PricedItem> items,
    required List<ComboSelection> combos,
    required Map<String, Object?> context,
    String? priceListId,
    String? promotionId,
    String voucher = '',
    int manual = 0,
    DateTime? at,
  }) async {
    require(Permission.sell);
    Future<CommercialRule?> find(String? id, String kind) async {
      if (id == null) return null;
      final rows = await db.rows(
        'SELECT * FROM commercial_rules WHERE store_id=? AND id=? AND active=1 AND kind=?',
        [storeId, id, kind],
      );
      if (rows.isEmpty) {
        throw StateError('Bảng giá/khuyến mãi đã ngừng hoặc không tồn tại.');
      }
      return CommercialRule.fromRow(rows.single);
    }

    final priceList = await find(priceListId, 'price_list'),
        promotion = await find(promotionId, 'promotion');
    final quantity = items.fold(0, (int n, i) => n + i.quantity),
        base = priceCart(items, const []);
    priceList?.requireEligible(
      school: context['school_id'] as String?,
      customerKind: context['customer_kind'] as String? ?? 'parent',
      issuedAt: at ?? clock(),
      quantity: quantity,
      amount: base.amount,
      combos: combos.isNotEmpty,
    );
    final price = priceCart(applyPriceList(priceList, items), combos);
    if (promotion == null && voucher.trim().isNotEmpty) {
      throw StateError('Chọn chương trình tương ứng với voucher.');
    }
    promotion?.requireEligible(
      school: context['school_id'] as String?,
      customerKind: context['customer_kind'] as String? ?? 'parent',
      issuedAt: at ?? clock(),
      quantity: quantity,
      amount: price.amount,
      combos: combos.isNotEmpty,
      voucher: voucher,
    );
    return CommercialQuote(
      price,
      promotion?.discount(
            price.amount,
            manual: manual,
            hasPriceList: priceList != null,
          ) ??
          0,
      priceList,
      promotion,
    );
  }

  Future<String> saveDealer({
    String? id,
    required String name,
    required String phone,
  }) async {
    require(Permission.catalog);
    if (name.trim().isEmpty) {
      throw ArgumentError('Nhập tên đại lý.');
    }
    return db.transaction(() async {
      if (id != null &&
          (await db.rows(
            "SELECT id FROM customers WHERE store_id=? AND id=? AND kind='dealer'",
            [storeId, id],
          )).isEmpty) {
        throw StateError('Đại lý không tồn tại.');
      }
      final target = id ?? uuid.v7();
      await db.execute(
        "INSERT INTO customers(id,store_id,name,phone,kind,updated_at,lww_key) VALUES (?,?,?,?,'dealer',?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,phone=excluded.phone,updated_at=excluded.updated_at,lww_key=excluded.lww_key",
        [
          target,
          storeId,
          name.trim(),
          phone.trim(),
          now,
          '$now|$deviceId|${uuid.v7()}',
        ],
      );
      await audit(
        'DEALER_SAVE',
        'customer',
        target,
        changes: {'name': name.trim(), 'phone': phone.trim()},
      );
      await enqueue('dealer', {'id': target}, 3);
      return target;
    });
  }
}
