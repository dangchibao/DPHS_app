import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';

import 'dart:typed_data';

import '../../core/media/media_service.dart';

extension CatalogService on LocalService {
  Future<void> saveVariant({
    Map<String, Object?>? existing,
    String? parentId,
    required String name,
    required String category,
    required String gender,
    required String level,
    required String year,
    required String size,
    required String color,
    required String unit,
    required String sku,
    required String barcode,
    required int price,
    required int cost,
    required int threshold,
    bool imageChanged = false,
    Uint8List? image,
  }) async {
    final actor = require(Permission.catalog);
    if ([
          name,
          category,
          gender,
          level,
          year,
          size,
          color,
          unit,
          sku,
        ].any((s) => s.trim().isEmpty) ||
        price < 0 ||
        cost < 0 ||
        price > 9007199254740991 ||
        cost > 9007199254740991 ||
        threshold < 0 ||
        threshold > 9007199254740991) {
      throw ArgumentError(
        'Kiểm tra các trường bắt buộc, giá và ngưỡng cảnh báo.',
      );
    }
    await db.transaction(() async {
      if (require(Permission.catalog).userId != actor.userId) {
        throw StateError('Phiên đã thay đổi.');
      }
      final productId =
              existing?['product_id'] as String? ?? parentId ?? uuid.v7(),
          variantId = existing?['id'] as String? ?? uuid.v7();
      if (existing == null && parentId == null) {
        await db.execute(
          'INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES (?,?,?,?,?,?,?)',
          [productId, name.trim(), category, gender, level, year, now],
        );
      } else {
        await db.execute(
          'UPDATE products SET name=?,category=?,gender=?,school_level=?,school_year=?,updated_at=?,version=version+1 WHERE id=?',
          [name.trim(), category, gender, level, year, now, productId],
        );
      }
      if (existing == null) {
        await db.execute(
          'INSERT INTO product_variants(id,product_id,sku,barcode,size,color,unit,cost,price,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            variantId,
            productId,
            sku.trim(),
            barcode.trim().isEmpty ? null : barcode.trim(),
            size.trim(),
            color.trim(),
            unit,
            cost,
            price,
            now,
          ],
        );
      } else {
        await db.execute(
          'UPDATE product_variants SET sku=?,barcode=?,size=?,color=?,unit=?,cost=?,price=?,updated_at=?,lww_key=?,version=version+1 WHERE id=?',
          [
            sku.trim(),
            barcode.trim().isEmpty ? null : barcode.trim(),
            size.trim(),
            color.trim(),
            unit,
            cost,
            price,
            now,
            '$now|$deviceId|${uuid.v7()}',
            variantId,
          ],
        );
      }
      if (imageChanged) {
        final reference = image == null ? null : await stageProductImage(image);
        await db.execute('UPDATE products SET image_path=? WHERE id=?', [
          reference,
          productId,
        ]);
      }
      final previousThreshold = await db.rows(
        'SELECT low_stock_threshold FROM store_variant_settings WHERE store_id=? AND variant_id=?',
        [storeId, variantId],
      );
      final priorRules = await db.rows(
        'SELECT id FROM stock_threshold_rules WHERE store_id=? AND variant_id=? LIMIT 1',
        [storeId, variantId],
      );
      String? thresholdId;
      if (priorRules.isEmpty ||
          previousThreshold.isEmpty ||
          previousThreshold.single['low_stock_threshold'] != threshold) {
        thresholdId = uuid.v7();
        final stamp = DateTime.fromMillisecondsSinceEpoch(
          clock().toUtc().millisecondsSinceEpoch,
          isUtc: true,
        ).toIso8601String();
        await db.execute(
          'INSERT INTO stock_threshold_rules VALUES(?,?,?,?,?,?,?,?)',
          [
            thresholdId,
            storeId,
            deviceId,
            actor.userId,
            variantId,
            threshold,
            '$stamp|$deviceId|$thresholdId',
            stamp,
          ],
        );
      }
      final actualThreshold = (await db.rows(
        'SELECT low_stock_threshold FROM store_variant_settings WHERE store_id=? AND variant_id=?',
        [storeId, variantId],
      )).single['low_stock_threshold'];
      await audit(
        existing == null ? 'PRODUCT_CREATE' : 'PRODUCT_UPDATE',
        'variant',
        variantId,
        changes: {
          'before': existing == null
              ? null
              : {
                  'price': existing['price'],
                  'cost': existing['cost'],
                  'size': existing['size'],
                  'color': existing['color'],
                },
          'after': {
            'low_stock_threshold': actualThreshold,
            'previous_threshold': previousThreshold.isEmpty
                ? null
                : previousThreshold.single['low_stock_threshold'],
            'image_changed': imageChanged,
            'name': name,
            'price': price,
            'cost': cost,
            'size': size,
            'color': color,
          },
        },
      );
      await enqueue('catalog', {
        'product_id': productId,
        'variant_id': variantId,
        'threshold_id': ?thresholdId,
      }, 3);
    });
  }

  Future<void> archiveVariant(String id, String reason) async {
    require(Permission.catalog);
    if (reason.trim().isEmpty) throw ArgumentError('Nhập lý do ngừng bán.');
    await db.transaction(() async {
      await db.execute(
        'UPDATE product_variants SET active=0,updated_at=?,version=version+1 WHERE id=?',
        [now, id],
      );
      await audit(
        'PRODUCT_ARCHIVE',
        'variant',
        id,
        reason: reason,
        severity: 'sensitive',
      );
      final variant = (await db.rows(
        'SELECT product_id FROM product_variants WHERE id=?',
        [id],
      )).single;
      await enqueue('catalog', {
        'product_id': variant['product_id'],
        'variant_id': id,
      }, 3);
    });
  }

  Future<List<Map<String, Object?>>> stockHistory(String id) {
    require(Permission.stock);
    return db.rows(
      'SELECT m.*,u.display_name FROM stock_movements m JOIN users u ON u.id=m.user_id WHERE m.store_id=? AND m.variant_id=? ORDER BY m.created_at DESC LIMIT 200',
      [storeId, id],
    );
  }

  Future<String?> suggestSize(String category, int height, int weight) async {
    final rules = await db.rows(
      'SELECT size FROM size_chart_rules WHERE category=? AND min_height<=? AND max_height>=? AND min_weight<=? AND max_weight>=? ORDER BY priority DESC,id LIMIT 1',
      [category, height, height, weight, weight],
    );
    return rules.isEmpty ? null : rules.first['size'] as String;
  }
}
