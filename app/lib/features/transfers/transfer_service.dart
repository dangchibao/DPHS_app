import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../pos/sales_service.dart';
import '../reservations/reservation_service.dart';

class TransferResult {
  const TransferResult(this.id, this.code);
  final String id, code;
}

String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

extension Transfers on LocalService {
  Future<List<Map<String, Object?>>> transferTargets() async {
    require(Permission.stock);
    final rows = await db.rows(
      "SELECT value FROM local_settings WHERE key='transfer_targets'",
    );
    return rows.isEmpty
        ? []
        : (jsonDecode(rows.single['value'] as String) as List)
              .map((r) => Map<String, Object?>.from(r as Map))
              .where((r) => r['store_id'] != storeId)
              .toList();
  }

  Future<List<Map<String, Object?>>> outgoingTransfers() {
    require(Permission.stock);
    return db.rows(
      """SELECT d.*,EXISTS(SELECT 1 FROM transfer_events e WHERE e.store_id=d.store_id AND e.document_id=d.id) AS dispatched,
      x.receipt_code,x.counts_json AS received_counts,x.reason AS receipt_reason,x.receiver_name,x.created_at AS received_at,
      (SELECT json_group_array(json_object('variant_id',l.variant_id,'name',l.name,'size',l.size,'color',l.color,'unit',l.unit,'quantity',l.quantity)) FROM invoice_lines l WHERE l.store_id=d.store_id AND l.document_id=d.id) AS items_json
      FROM documents d LEFT JOIN transfer_deliveries x ON x.store_id=d.store_id AND x.document_id=d.id
      WHERE d.store_id=? AND d.type='CK' AND d.kind='transfer_out' ORDER BY d.issued_at DESC LIMIT 300""",
      [storeId],
    );
  }

  Future<List<Map<String, Object?>>> incomingTransfers() {
    require(Permission.stock);
    return db.rows(
      'SELECT o.*,r.id AS receipt_id,r.counts_json AS received_counts,r.reason AS receipt_reason FROM transfer_offers o LEFT JOIN transfer_receipts r ON r.store_id=o.store_id AND r.offer_id=o.id WHERE o.store_id=? AND o.device_id=? ORDER BY o.dispatched_at DESC LIMIT 300',
      [storeId, deviceId],
    );
  }

  Future<TransferResult> createTransferOut({
    required String targetDeviceId,
    required List<CartItem> items,
    required String reason,
    String? commandId,
  }) async {
    final actor = require(Permission.stock);
    if (reason.trim().isEmpty ||
        reason.length > 1000 ||
        items.isEmpty ||
        items.length > 20 ||
        items.any((i) => i.quantity < 1 || i.quantity > 100000)) {
      throw ArgumentError('Chuyển kho cần lý do và 1–20 biến thể hợp lệ.');
    }
    final id = commandId ?? uuid.v7(),
        hash = _hash({
          'target': targetDeviceId,
          'items': [
            for (final i in items)
              {'variant_id': i.variantId, 'quantity': i.quantity},
          ],
          'reason': reason.trim(),
        });
    return db.transaction(() async {
      final prior = await _existingTransfer(id, hash);
      if (prior != null) return prior;
      final targets = (await transferTargets())
          .where((r) => r['device_id'] == targetDeviceId)
          .toList();
      if (targets.length != 1) {
        throw StateError(
          'Chưa có máy nhận được duyệt. Kết nối và đồng bộ danh sách điểm nhận trước.',
        );
      }
      final target = targets.single, quantities = <String, int>{};
      for (final item in items) {
        quantities.update(
          item.variantId,
          (n) => n + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
      final lines = <Map<String, Object?>>[];
      final catalogRows = await catalog();
      for (final entry in quantities.entries) {
        if (entry.value > 100000 ||
            await availableQuantity(entry.key) < entry.value) {
          throw StateError(
            'Không đủ tồn khả dụng để chuyển; kiểm tra phần đang giữ.',
          );
        }
        final variant = catalogRows
            .where((r) => r['id'] == entry.key)
            .firstOrNull;
        if (variant == null) {
          throw StateError('Sản phẩm đã ngừng bán hoặc không tồn tại.');
        }
        lines.add({...variant, 'quantity': entry.value});
      }
      final time = now,
          code = await allocateDocumentCode(
            'CK',
            issuedAt: DateTime.parse(time),
          );
      await db.execute(
        'INSERT INTO documents VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          'CK',
          'transfer_out',
          code,
          time,
          actor.userId,
          null,
          null,
          0,
          0,
          0,
          lines.first['school_year'],
          jsonEncode({
            'target_store_id': target['store_id'],
            'target_device_id': targetDeviceId,
            'target_store_code': target['store_code'],
            'target_device_code': target['device_code'],
            'notes': reason.trim(),
            'command_hash': hash,
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
            0,
            line['cost'],
            0,
            line['lww_key'],
          ],
        );
      }
      for (final line in lines) {
        await db.execute(
          'INSERT INTO stock_movements VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            deviceId,
            line['id'],
            -(line['quantity'] as int),
            'transfer_out',
            id,
            'Xuất chuyển $code',
            actor.userId,
            time,
          ],
        );
      }
      await audit(
        'TRANSFER_OUT',
        'document',
        id,
        reason: reason.trim(),
        severity: 'sensitive',
        changes: {
          'target_store_id': target['store_id'],
          'target_device_id': targetDeviceId,
          'items': quantities,
        },
      );
      await enqueue('transfer_out', {'id': id}, 0);
      return TransferResult(id, code);
    });
  }

  Future<TransferResult?> _existingTransfer(String id, String hash) async {
    final rows = await db.rows(
      'SELECT id,code,metadata_json FROM documents WHERE store_id=? AND id=?',
      [storeId, id],
    );
    if (rows.isEmpty) return null;
    if ((jsonDecode(rows.single['metadata_json'] as String)
            as Map)['command_hash'] !=
        hash) {
      throw StateError('ID chuyển kho đã dùng với nội dung khác.');
    }
    return TransferResult(id, rows.single['code'] as String);
  }

  Future<void> dispatchTransfer(String id, String reason) async {
    final actor = require(Permission.stock);
    if (reason.trim().isEmpty || reason.length > 200) {
      throw ArgumentError('Cần lý do chuyển (tối đa 200 ký tự).');
    }
    await db.transaction(() async {
      final doc = await db.rows(
        "SELECT id FROM documents WHERE store_id=? AND device_id=? AND id=? AND type='CK' AND kind='transfer_out'",
        [storeId, deviceId, id],
      );
      final previous = await db.rows(
        'SELECT id FROM transfer_events WHERE store_id=? AND document_id=?',
        [storeId, id],
      );
      if (doc.isEmpty || previous.isNotEmpty) {
        throw StateError('Phiếu không thuộc máy hoặc đã chuyển.');
      }
      final event = uuid.v7();
      await db.execute('INSERT INTO transfer_events VALUES (?,?,?,?,?,?,?)', [
        event,
        storeId,
        deviceId,
        id,
        actor.userId,
        reason.trim(),
        now,
      ]);
      await audit('TRANSFER_DISPATCH', 'document', id, reason: reason.trim());
      await enqueue('transfer_dispatch', {'id': event}, 0);
    });
  }

  Future<TransferResult> receiveTransfer({
    required String offerId,
    required Map<String, int> quantities,
    required String reason,
    String? commandId,
  }) async {
    final actor = require(Permission.stock);
    if (reason.trim().isEmpty ||
        reason.length > 200 ||
        quantities.values.any((n) => n < 0 || n > 100000)) {
      throw ArgumentError(
        'Cần lý do nhận/chênh lệch và số lượng thực nhận hợp lệ.',
      );
    }
    final id = commandId ?? uuid.v7(),
        hash = _hash({
          'offer': offerId,
          'counts': quantities,
          'reason': reason.trim(),
        });
    return db.transaction(() async {
      final prior = await _existingTransfer(id, hash);
      if (prior != null) return prior;
      final offers = await db.rows(
        'SELECT * FROM transfer_offers WHERE store_id=? AND device_id=? AND id=?',
        [storeId, deviceId, offerId],
      );
      final previous = await db.rows(
        'SELECT id FROM transfer_receipts WHERE store_id=? AND offer_id=?',
        [storeId, offerId],
      );
      if (offers.isEmpty || previous.isNotEmpty) {
        throw StateError(
          'Phiếu không thuộc máy nhận, chưa đồng bộ hoặc đã nhận.',
        );
      }
      final offer = offers.single, time = now;
      if ((offer['dispatched_at'] as String).compareTo(time) > 0) {
        throw StateError('Ngày nhận trước ngày chuyển. Kiểm tra giờ máy.');
      }
      final items = (jsonDecode(offer['items_json'] as String) as List)
          .map((r) => Map<String, Object?>.from(r as Map))
          .toList();
      if (quantities.length != items.length ||
          items.any((i) => !quantities.containsKey(i['variant_id']))) {
        throw StateError('Cần ghi thực nhận từng món, kể cả 0.');
      }
      final code = await allocateDocumentCode(
        'CK',
        issuedAt: DateTime.parse(time),
      );
      await db.execute(
        'INSERT INTO documents VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          'CK',
          'transfer_in',
          code,
          time,
          actor.userId,
          null,
          null,
          0,
          0,
          0,
          offer['school_year'],
          jsonEncode({
            'offer_id': offerId,
            'source_code': offer['source_code'],
            'source_store_id': offer['source_store_id'],
            'command_hash': hash,
          }),
        ],
      );
      for (final item in items) {
        final quantity = quantities[item['variant_id']]!;
        if (quantity > 0) {
          await db.execute(
            'INSERT INTO invoice_lines VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              uuid.v7(),
              storeId,
              id,
              item['variant_id'],
              item['name'],
              item['size'],
              item['color'],
              item['unit'],
              quantity,
              0,
              item['unit_cost'],
              0,
              item['price_version'],
            ],
          );
        }
      }
      await db.execute(
        'INSERT INTO transfer_receipts VALUES (?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          offerId,
          actor.userId,
          jsonEncode([
            for (final item in items)
              {
                'variant_id': item['variant_id'],
                'quantity': quantities[item['variant_id']],
              },
          ]),
          reason.trim(),
          time,
        ],
      );
      for (final item in items) {
        final quantity = quantities[item['variant_id']]!;
        if (quantity > 0) {
          await db.execute(
            'INSERT INTO stock_movements VALUES (?,?,?,?,?,?,?,?,?,?)',
            [
              uuid.v7(),
              storeId,
              deviceId,
              item['variant_id'],
              quantity,
              'transfer_in',
              id,
              'Nhận chuyển $code',
              actor.userId,
              time,
            ],
          );
        }
      }
      await audit(
        'TRANSFER_RECEIVE',
        'document',
        id,
        reason: reason.trim(),
        severity: 'sensitive',
        changes: {
          'source_id': offerId,
          'counts': [
            for (final item in items)
              {
                'variant_id': item['variant_id'],
                'expected': item['quantity'],
                'actual': quantities[item['variant_id']],
              },
          ],
        },
      );
      await enqueue('transfer_in', {'id': id}, 0);
      return TransferResult(id, code);
    });
  }
}
