import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../pos/sales_service.dart';
import '../pos/pricing.dart';
import '../schools/school_service.dart';
import 'tailoring_rule.dart';

extension TailoringService on LocalService {
  Future<List<Map<String, Object?>>> tailoringRules({bool activeOnly = false}) {
    require(Permission.tailoring);
    return db.rows(
      'SELECT * FROM tailoring_rules WHERE store_id=? ${activeOnly ? 'AND active=1' : ''} ORDER BY name',
      [storeId],
    );
  }

  Future<String> saveTailoringRule({
    String? id,
    required String name,
    required Map<String, Object?> config,
    bool active = true,
  }) async {
    require(Permission.catalog);
    return db.transaction(() async {
      if (id != null &&
          (await db.rows(
            'SELECT id FROM tailoring_rules WHERE store_id=? AND id=?',
            [storeId, id],
          )).isEmpty) {
        throw StateError('Không tìm thấy bảng phụ thu.');
      }
      final target = id ?? uuid.v7(),
          rule = TailoringRule(
            id: target,
            version: '$now|$deviceId|${uuid.v7()}',
            name: name.trim(),
            config: config,
          );
      await db.execute(
        'INSERT INTO tailoring_rules VALUES (?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,config_json=excluded.config_json,active=excluded.active,updated_at=excluded.updated_at,lww_key=excluded.lww_key',
        [
          target,
          storeId,
          rule.name,
          jsonEncode(config),
          active ? 1 : 0,
          now,
          rule.version,
        ],
      );
      await audit(
        'TAILOR_RULE_SAVE',
        'tailoring_rule',
        target,
        reason: 'Cập nhật bảng phụ thu may',
        severity: 'sensitive',
        changes: {'name': rule.name, 'config': config, 'active': active},
      );
      await enqueue('tailoring_rule', {'id': target}, 3);
      return target;
    });
  }

  Future<SaleResult> createTailoring({
    required List<CartItem> items,
    required String ruleId,
    required Map<String, int> measurements,
    required List<String> options,
    required String dueDate,
    required String notes,
    required String customerName,
    required String phone,
    required int received,
    required String method,
    String? customerId,
    String? schoolId,
    String? studentId,
    String? commandId,
    int? expectedTotal,
  }) async {
    final actor = require(Permission.sell);
    if (items.isEmpty ||
        items.length > 20 ||
        items.any((i) => i.quantity < 1 || i.quantity > 100000) ||
        items.map((i) => i.variantId).toSet().length != items.length ||
        !['cash', 'bank'].contains(method) ||
        received < 0 ||
        received > maximumMoney ||
        notes.length > 4000) {
      throw ArgumentError('Đơn may hoặc thanh toán không hợp lệ.');
    }
    final date = DateTime.tryParse('${dueDate}T00:00:00.000Z');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dueDate) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != dueDate ||
        dueDate.compareTo(
              clock()
                  .toUtc()
                  .add(const Duration(hours: 7))
                  .toIso8601String()
                  .substring(0, 10),
            ) <
            0) {
      throw ArgumentError('Ngày hẹn không được trước ngày nhận.');
    }
    final id = commandId ?? uuid.v7(),
        requestHash = sha256
            .convert(
              utf8.encode(
                jsonEncode({
                  'items': [
                    for (final i in items)
                      {'variant': i.variantId, 'quantity': i.quantity},
                  ],
                  'rule_id': ruleId,
                  'measurements': {
                    for (final k in measurementLabels.keys) k: measurements[k],
                  },
                  'options': options,
                  'due_date': dueDate,
                  'notes': notes,
                  'customer': customerName,
                  'phone': phone,
                  'customer_id': customerId,
                  'school_id': schoolId,
                  'student_id': studentId,
                  'received': received,
                  'method': method,
                  'expected_total': expectedTotal,
                }),
              ),
            )
            .toString();
    return db.transaction(() async {
      final prior = await db.rows(
        'SELECT * FROM documents WHERE store_id=? AND id=?',
        [storeId, id],
      );
      if (prior.isNotEmpty) {
        final d = prior.single,
            m = jsonDecode(d['metadata_json'] as String) as Map;
        if (d['type'] != 'MR' || m['command_hash'] != requestHash) {
          throw StateError('ID đặt may đã dùng với nội dung khác.');
        }
        return SaleResult(
          id,
          d['code'] as String,
          d['total'] as int,
          m['paid'] as int,
          m['change'] as int,
        );
      }
      final current = require(Permission.sell);
      if (current.userId != actor.userId) {
        throw StateError('Phiên đã đổi người dùng. Vui lòng thực hiện lại.');
      }
      final time = now;
      final receivedDay = DateTime.parse(time)
          .add(const Duration(hours: 7))
          .toIso8601String()
          .substring(0, 10);
      if (dueDate.compareTo(receivedDay) < 0) {
        throw ArgumentError('Ngày hẹn không được trước ngày nhận.');
      }
      final rows = await db.rows(
        'SELECT * FROM tailoring_rules WHERE store_id=? AND id=? AND active=1',
        [storeId, ruleId],
      );
      if (rows.isEmpty) {
        throw StateError('Chọn bảng phụ thu đang áp dụng.');
      }
      final rule = TailoringRule.fromRow(rows.single),
          fee = rule.fee(measurements, options),
          variants = <Map<String, Object?>>[];
      var sum = BigInt.zero;
      for (final item in items) {
        final rows = await db.rows(
          'SELECT v.*,p.name,p.school_year FROM product_variants v JOIN products p ON p.id=v.product_id WHERE v.id=? AND v.active=1 AND p.active=1',
          [item.variantId],
        );
        if (rows.isEmpty) {
          throw StateError('Mẫu sản phẩm đã ngừng bán.');
        }
        final v = rows.single,
            price = checkedMoney(
              BigInt.from(v['price'] as int) + BigInt.from(fee),
            );
        v['quantity'] = item.quantity;
        v['custom_price'] = price;
        variants.add(v);
        sum += BigInt.from(price) * BigInt.from(item.quantity);
      }
      final total = checkedMoney(sum),
          paid = received > total ? total : received;
      if (expectedTotal != null && expectedTotal != total) {
        throw StateError('Giá/phụ thu đã thay đổi. Kiểm tra lại tổng tiền.');
      }
      final context = await schoolSaleContext(
            customerId: customerId,
            schoolId: schoolId,
            studentId: studentId,
          ),
          name = context['customer_name'] as String? ?? customerName.trim(),
          contact = context['phone'] as String? ?? phone.trim();
      if (name.isEmpty || name.length > 200) {
        throw ArgumentError('Đơn may cần tên khách hàng.');
      }
      final resolvedCustomer = context['customer_id'] as String?;
      final customer = resolvedCustomer ?? uuid.v7();
      if (resolvedCustomer == null) {
        await db.execute(
          "INSERT INTO customers(id,store_id,name,phone,kind,updated_at) VALUES (?,?,?,?,'parent',?)",
          [customer, storeId, name, contact, time],
        );
      }
      final code = await allocateDocumentCode(
        'MR',
        issuedAt: DateTime.parse(time),
      );
      final data = {
        'rule': rule.proof,
        'rule_name': rule.name,
        'measurements': measurements,
        'options': options,
        'option_labels': [
          for (final key in options)
            ((rule.config['options'] as Map)[key] as Map)['label'],
        ],
        'per_unit_fee': fee,
        'due_date': dueDate,
        'notes': notes.trim(),
      };
      await db.execute(
        'INSERT INTO documents VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          'MR',
          'tailoring',
          code,
          time,
          actor.userId,
          customer,
          null,
          total,
          0,
          total,
          context['academic_year'] ?? variants.first['school_year'],
          jsonEncode({
            ...context,
            'customer_name': name,
            'phone': contact,
            'tailoring': data,
            'paid': paid,
            'change': received - paid,
            'command_hash': requestHash,
          }),
        ],
      );
      for (final v in variants) {
        await db.execute(
          'INSERT INTO invoice_lines VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            id,
            v['id'],
            v['name'],
            'May riêng',
            v['color'],
            v['unit'],
            v['quantity'],
            v['custom_price'],
            v['cost'],
            0,
            v['lww_key'],
          ],
        );
      }
      if (paid > 0) {
        await db.execute('INSERT INTO payments VALUES (?,?,?,?,?,?,?,?,?,?)', [
          uuid.v7(),
          storeId,
          deviceId,
          id,
          actor.userId,
          paid,
          method,
          'receive',
          time,
          'Đặt cọc / thanh toán may riêng',
        ]);
      }
      if (paid < total) {
        await db.execute(
          'INSERT INTO receivable_entries VALUES (?,?,?,?,?,?,?,?)',
          [uuid.v7(), storeId, customer, id, null, total - paid, dueDate, time],
        );
      }
      await audit(
        'TAILOR_CREATE',
        'document',
        id,
        reason: 'Nhận đặt may riêng',
        changes: {
          'code': code,
          'total': total,
          'paid': paid,
          'due_date': dueDate,
          'surcharge_per_unit': fee,
        },
      );
      if (paid > 0) {
        await audit(
          'PAYMENT_RECEIVE',
          'document',
          id,
          changes: {'amount': paid, 'method': method},
        );
      }
      await enqueue('tailoring', {'id': id}, 0);
      return SaleResult(id, code, total, paid, received - paid);
    });
  }

  Future<List<Map<String, Object?>>> tailoringOrders() {
    require(Permission.tailoring);
    return db.rows(
      "SELECT d.*,c.name AS customer_name,c.phone,CASE WHEN EXISTS(SELECT 1 FROM document_events e WHERE e.store_id=d.store_id AND e.document_id=d.id AND e.type='TAILOR_DELIVERED') THEN 3 WHEN EXISTS(SELECT 1 FROM document_events e WHERE e.store_id=d.store_id AND e.document_id=d.id AND e.type='TAILOR_READY') THEN 2 WHEN EXISTS(SELECT 1 FROM document_events e WHERE e.store_id=d.store_id AND e.document_id=d.id AND e.type='TAILOR_SEWING') THEN 1 ELSE 0 END AS status,COALESCE((SELECT SUM(r.amount) FROM receivable_ledger r WHERE r.store_id=d.store_id AND r.document_id=d.id),0) AS debt FROM documents d JOIN customers c ON c.store_id=d.store_id AND c.id=d.customer_id WHERE d.store_id=? AND d.type='MR' AND d.kind='tailoring' ORDER BY d.issued_at DESC LIMIT 300",
      [storeId],
    );
  }

  Future<String> advanceTailoring({
    required String documentId,
    required int nextStatus,
    required String reason,
    String? commandId,
  }) async {
    final actor = require(Permission.tailoring);
    if (nextStatus < 1 ||
        nextStatus > 3 ||
        reason.trim().isEmpty ||
        reason.length > 200) {
      throw ArgumentError('Chọn trạng thái tiếp theo và ghi chú.');
    }
    final id = commandId ?? uuid.v7();
    return db.transaction(() async {
      final previous = await db.rows(
        'SELECT * FROM document_events WHERE id=?',
        [id],
      );
      if (previous.isNotEmpty) {
        final e = previous.single;
        if (e['store_id'] != storeId ||
            e['document_id'] != documentId ||
            e['type'] != tailoringSteps[nextStatus - 1] ||
            e['reason'] != reason.trim() ||
            e['user_id'] != actor.userId) {
          throw StateError('ID cập nhật đã dùng với nội dung khác.');
        }
        return id;
      }
      final docs = await db.rows(
        "SELECT device_id,issued_at FROM documents WHERE store_id=? AND id=? AND type='MR' AND kind='tailoring'",
        [storeId, documentId],
      );
      final order = docs.firstOrNull;
      if (order == null || order['device_id'] != deviceId) {
        throw StateError('Cập nhật may offline trên máy lập phiếu.');
      }
      if (DateTime.parse(now)
          .isBefore(DateTime.parse(order['issued_at'] as String))) {
        throw StateError(
          'Đồng hồ đang trước ngày nhận phiếu. Kiểm tra lại thời gian máy.',
        );
      }
      final events = await db.rows(
        'SELECT type FROM document_events WHERE store_id=? AND document_id=?',
        [storeId, documentId],
      );
      var status = 0;
      for (final event in events) {
        final rank = tailoringSteps.indexOf(event['type'] as String) + 1;
        if (rank > status) {
          status = rank;
        }
      }
      if (status != nextStatus - 1) {
        throw StateError('Không được bỏ qua, lùi hoặc lặp trạng thái.');
      }
      await db.execute('INSERT INTO document_events VALUES (?,?,?,?,?,?,?,?)', [
        id,
        storeId,
        documentId,
        tailoringSteps[nextStatus - 1],
        null,
        reason.trim(),
        actor.userId,
        now,
      ]);
      await audit(
        'TAILOR_STATUS',
        'document',
        documentId,
        reason: reason.trim(),
        changes: {
          'from': tailoringStatuses[nextStatus - 1],
          'to': tailoringStatuses[nextStatus],
        },
      );
      await enqueue('tailoring_event', {'id': id}, 0);
      return id;
    });
  }
}
