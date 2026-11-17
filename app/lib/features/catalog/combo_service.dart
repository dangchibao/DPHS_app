import 'dart:convert';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../pos/pricing.dart';

ComboDefinition comboFromRow(Map<String, Object?> row) => ComboDefinition(
  id: row['id'] as String,
  version: row['lww_key'] as String,
  name: row['name'] as String,
  price: row['price'] as int,
  parts: (jsonDecode(row['items_json'] as String) as List)
      .map((r) => ComboPart.fromJson(Map<String, Object?>.from(r as Map)))
      .toList(),
);

extension ComboService on LocalService {
  Future<List<Map<String, Object?>>> comboRules({bool activeOnly = false}) {
    final actor = session;
    if (actor == null) {
      throw StateError('Vui lòng đăng nhập.');
    }
    final allowed = permissionsByRole[actor.role]!;
    final permission = [
      Permission.sell,
      Permission.catalog,
      Permission.stock,
      Permission.reports,
    ].where(allowed.contains).firstOrNull;
    if (permission == null) {
      throw StateError('Không có quyền xem combo.');
    }
    actor.require(permission, storeId, clock());
    return db.rows(
      'SELECT * FROM combo_rules WHERE store_id=? ${activeOnly ? 'AND active=1' : ''} ORDER BY active DESC,name',
      [storeId],
    );
  }

  Future<String> saveCombo({
    String? id,
    required String name,
    required int price,
    required List<ComboPart> parts,
    bool active = true,
  }) async {
    require(Permission.catalog);
    if (name.trim().isEmpty ||
        price < 0 ||
        price > maximumMoney ||
        parts.isEmpty ||
        parts.length > 20 ||
        parts.any(
          (p) => p.productId.isEmpty || p.quantity <= 0 || p.quantity > 100000,
        )) {
      throw ArgumentError(
        'Nhập tên, giá nguyên VND và từ 1 đến 20 món thành phần.',
      );
    }
    return db.transaction(() async {
      final before = id == null
          ? <Map<String, Object?>>[]
          : await db.rows(
              'SELECT * FROM combo_rules WHERE store_id=? AND id=?',
              [storeId, id],
            );
      if (id != null && before.isEmpty) {
        throw StateError('Không tìm thấy combo.');
      }
      for (final part in parts) {
        final found = await db.rows(
          'SELECT id,active FROM products WHERE id=?',
          [part.productId],
        );
        if (found.isEmpty || (active && found.single['active'] != 1)) {
          throw StateError('Món thành phần không tồn tại hoặc đã ngừng bán.');
        }
      }
      final target = id ?? uuid.v7(),
          version = '$now|$deviceId|${uuid.v7()}',
          items = jsonEncode(parts.map((p) => p.toJson()).toList());
      await db.execute(
        'INSERT INTO combo_rules VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,price=excluded.price,items_json=excluded.items_json,active=excluded.active,updated_at=excluded.updated_at,lww_key=excluded.lww_key',
        [
          target,
          storeId,
          name.trim(),
          price,
          items,
          active ? 1 : 0,
          now,
          version,
        ],
      );
      await audit(
        'COMBO_SAVE',
        'combo',
        target,
        severity: 'sensitive',
        reason: 'Cập nhật giá và thành phần combo',
        changes: {
          'before': before.firstOrNull,
          'after': {
            'name': name.trim(),
            'price': price,
            'parts': parts.map((p) => p.toJson()).toList(),
            'active': active,
          },
        },
      );
      await enqueue('combo', {'id': target}, 3);
      return target;
    });
  }

  Future<List<ComboSelection>> approvedCombos(
    List<ComboSelection> selected,
  ) async {
    require(Permission.sell);
    if (selected.length > 20) {
      throw ArgumentError('Một giỏ có tối đa 20 nhóm combo.');
    }
    final approved = <ComboSelection>[];
    for (final group in selected) {
      final rows = await db.rows(
        'SELECT * FROM combo_rules WHERE store_id=? AND id=? AND active=1',
        [storeId, group.rule.id],
      );
      if (rows.isEmpty || rows.single['lww_key'] != group.rule.version) {
        throw StateError(
          'Combo đã đổi giá, thành phần hoặc ngừng bán. Xóa và chọn lại combo trước khi thanh toán.',
        );
      }
      approved.add(
        ComboSelection(
          rule: comboFromRow(rows.single),
          picks: List.of(group.picks),
          quantity: group.quantity,
        ),
      );
    }
    return approved;
  }
}
