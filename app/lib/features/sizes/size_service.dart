import 'dart:convert';

import '../../core/auth/permissions.dart';
import '../../core/local_service.dart';
import 'size_rule.dart';

extension SizeService on LocalService {
  Future<List<Map<String, Object?>>> sizeRules() {
    final actor = session;
    if (actor == null) throw StateError('Vui lòng đăng nhập.');
    require(
      actor.can(Permission.catalog)
          ? Permission.catalog
          : actor.can(Permission.sell)
          ? Permission.sell
          : Permission.stock,
    );
    return db.rows(
      'SELECT r.*,p.name AS product_name FROM size_rules r LEFT JOIN products p ON p.id=r.product_id WHERE r.store_id=? ORDER BY r.name',
      [storeId],
    );
  }

  Future<void> saveSizeRule({
    String? id,
    required String name,
    String? productId,
    required SizeRule rule,
    bool active = true,
  }) async {
    require(Permission.catalog);
    rule.validate();
    if (name.trim().isEmpty || name.length > 200) {
      throw ArgumentError('Cần tên bảng size (tối đa 200 ký tự).');
    }
    if (productId != null &&
        (await db.rows('SELECT id FROM products WHERE id=?', [
          productId,
        ])).isEmpty) {
      throw StateError('Sản phẩm không tồn tại hoặc đã ngừng bán.');
    }
    await db.transaction(() async {
      final target = id ?? uuid.v7();
      if (id != null &&
          (await db.rows(
            'SELECT id FROM size_rules WHERE store_id=? AND id=?',
            [storeId, id],
          )).isEmpty) {
        throw StateError('Không tìm thấy bảng size tại cửa hàng.');
      }
      await db.execute(
        'INSERT INTO size_rules VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET product_id=excluded.product_id,name=excluded.name,config_json=excluded.config_json,active=excluded.active,updated_at=excluded.updated_at WHERE size_rules.store_id=excluded.store_id',
        [
          target,
          storeId,
          productId,
          name.trim(),
          jsonEncode(rule.rows),
          active ? 1 : 0,
          now,
          '',
        ],
      );
      await audit(
        'SIZE_RULE_SAVE',
        'size_rule',
        target,
        changes: {
          'name': name.trim(),
          'product_id': productId,
          'active': active,
          'rows': rule.rows,
        },
      );
      await enqueue('size_rule', {'id': target}, 3);
    });
  }
}
