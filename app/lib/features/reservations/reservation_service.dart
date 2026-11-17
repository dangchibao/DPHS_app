import 'dart:convert';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../pos/sales_service.dart';

extension Reservations on LocalService {
  Future<int> reservedQuantity(
    String variantId, {
    DateTime? at,
    bool allDevices = false,
    String? exclude,
  }) async {
    final instant = (at ?? clock()).toUtc().toIso8601String();
    final rows = await db.rows(
      '''SELECT COALESCE(SUM(r.quantity),0) AS n FROM reservation_lines r
      WHERE r.store_id=? AND r.variant_id=? AND (?=1 OR r.device_id=?)
      AND r.created_at<=? AND r.expires_at>? AND (? IS NULL OR r.document_id<>?)
      AND NOT EXISTS(SELECT 1 FROM reservation_events e WHERE e.store_id=r.store_id AND e.document_id=r.document_id AND e.created_at<=?)''',
      [
        storeId,
        variantId,
        allDevices ? 1 : 0,
        deviceId,
        instant,
        instant,
        exclude,
        exclude,
        instant,
      ],
    );
    return rows.single['n'] as int;
  }

  Future<int> availableQuantity(
    String variantId, {
    DateTime? at,
    String? exclude,
  }) async {
    final rows = await db.rows(
      'SELECT quantity FROM device_stock_allocations WHERE store_id=? AND device_id=? AND variant_id=?',
      [storeId, deviceId, variantId],
    );
    return (rows.isEmpty ? 0 : rows.single['quantity'] as int) -
        await reservedQuantity(variantId, at: at, exclude: exclude);
  }

  Future<Map<String, Object?>> activeReservation(
    String id, {
    DateTime? at,
  }) async {
    require(Permission.reserve);
    final rows = await db.rows(
      "SELECT * FROM documents WHERE store_id=? AND device_id=? AND id=? AND type='DH' AND kind='reservation'",
      [storeId, deviceId, id],
    );
    if (rows.isEmpty) {
      throw StateError('Phiếu giữ hàng không thuộc thiết bị này.');
    }
    final row = rows.single,
        meta = jsonDecode(row['metadata_json'] as String) as Map;
    final instant = (at ?? clock()).toUtc();
    if (DateTime.parse(row['issued_at'] as String).isAfter(instant) ||
        !DateTime.parse(meta['expires_at'] as String).isAfter(instant) ||
        (await db.rows(
          'SELECT id FROM reservation_events WHERE store_id=? AND document_id=?',
          [storeId, id],
        )).isNotEmpty) {
      throw StateError('Phiếu giữ hàng đã hết hạn, giải phóng hoặc giao.');
    }
    return row;
  }

  Future<String> reserveItems(
    List<CartItem> items, {
    required String name,
    String phone = '',
    required Duration duration,
    String notes = '',
  }) async {
    final actor = require(Permission.sell);
    if (name.trim().isEmpty ||
        name.length > 200 ||
        phone.length > 40 ||
        notes.length > 1000 ||
        duration.inMinutes < 1 ||
        duration > const Duration(days: 30) ||
        items.isEmpty ||
        items.length > 20 ||
        items.any((i) => i.quantity < 1 || i.quantity > 100000)) {
      throw ArgumentError(
        'Tên khách, thời hạn (1 phút–30 ngày) hoặc hàng giữ không hợp lệ.',
      );
    }
    return db.transaction(() async {
      final id = uuid.v7(),
          customer = uuid.v7(),
          issued = now,
          expiry = DateTime.parse(issued).add(duration).toIso8601String();
      final quantities = <String, int>{};
      for (final item in items) {
        quantities.update(
          item.variantId,
          (v) => v + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
      final lines = <Map<String, Object?>>[];
      var total = 0;
      for (final entry in quantities.entries) {
        if (entry.value > 100000 ||
            await availableQuantity(entry.key) < entry.value) {
          throw StateError('Không đủ tồn khả dụng để giữ hàng.');
        }
        final rows = await db.rows(
          '''SELECT v.*,p.name,p.school_year FROM product_variants v JOIN products p ON p.id=v.product_id WHERE v.id=? AND v.active=1 AND p.active=1''',
          [entry.key],
        );
        if (rows.isEmpty) throw StateError('Sản phẩm đã ngừng bán.');
        final row = rows.single;
        // Giá DH là báo giá tại thời điểm giữ; HD xác nhận lại giá khi giao.
        total += (row['price'] as int) * entry.value;
        row['quantity'] = entry.value;
        lines.add(row);
      }
      if (total > 9007199254740991) {
        throw StateError('Tổng báo giá vượt giới hạn.');
      }
      await db.execute(
        'INSERT INTO customers(id,store_id,name,phone,kind,updated_at) VALUES (?,?,?,?,?,?)',
        [customer, storeId, name.trim(), phone.trim(), 'parent', issued],
      );
      final code = await allocateDocumentCode(
        'DH',
        issuedAt: DateTime.parse(issued),
      );
      await db.execute(
        'INSERT INTO documents VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          'DH',
          'reservation',
          code,
          issued,
          actor.userId,
          customer,
          null,
          total,
          0,
          total,
          lines.first['school_year'],
          jsonEncode({
            'expires_at': expiry,
            'notes': notes.trim(),
            'customer_name': name.trim(),
            'phone': phone.trim(),
          }),
        ],
      );
      for (final line in lines) {
        await db.execute(
          'INSERT INTO invoice_lines VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            id,
            line['id'],
            line['name'],
            line['size'],
            line['color'],
            line['unit'],
            line['quantity'],
            line['price'],
            line['cost'],
            0,
            line['lww_key'],
          ],
        );
        await db.execute(
          'INSERT INTO reservation_lines VALUES (?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            deviceId,
            id,
            line['id'],
            line['quantity'],
            expiry,
            issued,
          ],
        );
      }
      await audit(
        'RESERVATION_CREATE',
        'document',
        id,
        changes: {'code': code, 'expires_at': expiry},
      );
      await enqueue('reservation', {'id': id}, 0);
      return id;
    });
  }

  Future<void> releaseReservation(String id, String reason) async {
    final actor = require(Permission.reserve);
    if (reason.trim().isEmpty || reason.length > 200) {
      throw ArgumentError('Cần lý do giải phóng (tối đa 200 ký tự).');
    }
    await db.transaction(() async {
      await activeReservation(id);
      final event = uuid.v7();
      await db.execute(
        'INSERT INTO reservation_events VALUES (?,?,?,?,?,?,?,?,?)',
        [
          event,
          storeId,
          deviceId,
          id,
          'release',
          null,
          actor.userId,
          reason.trim(),
          now,
        ],
      );
      await audit('RESERVATION_RELEASE', 'document', id, reason: reason.trim());
      await enqueue('reservation_event', {'id': event}, 0);
    });
  }

  Future<List<Map<String, Object?>>> reservations() {
    require(Permission.reserve);
    return db.rows(
      '''SELECT d.*,e.kind AS resolution FROM documents d LEFT JOIN reservation_events e ON e.store_id=d.store_id AND e.document_id=d.id
      WHERE d.store_id=? AND d.type='DH' AND d.kind='reservation' ORDER BY d.issued_at DESC LIMIT 300''',
      [storeId],
    );
  }
}
