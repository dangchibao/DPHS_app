import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../pos/sales_service.dart';
import '../pos/pricing.dart';
import 'return_pricing.dart';
import '../reservations/reservation_service.dart';

class ReturnQuote {
  ReturnQuote(
    this.original,
    this.returned,
    this.variants,
    this.replacements,
    this.returnedValue,
    this.replacementValue,
    this.settlement,
  );
  final Map<String, Object?> original;
  final List<Map<String, Object?>> returned;
  final Map<String, Map<String, Object?>> variants;
  final Map<String, ReplacementPrice> replacements;
  final int returnedValue, replacementValue;
  final ReturnSettlement settlement;
}

class ReturnResult {
  ReturnResult(this.id, this.code, this.settlement);
  final String id, code;
  final ReturnSettlement settlement;
}

extension ReturnService on LocalService {
  Future<List<Map<String, Object?>>> returnableDocuments({String search = ''}) {
    require(Permission.returns);
    return db.rows(
      "SELECT d.*,COALESCE(c.name,json_extract(d.metadata_json,'\$.customer_name'),'') AS customer_name FROM documents d LEFT JOIN customers c ON c.store_id=d.store_id AND c.id=d.customer_id WHERE d.store_id=? AND ((d.type='HD' AND d.kind='sale') OR (d.type='DT' AND d.kind IN ('return','exchange'))) AND NOT EXISTS(SELECT 1 FROM document_events e WHERE e.store_id=d.store_id AND e.document_id=d.id AND e.type='CANCELLED') AND EXISTS(SELECT 1 FROM invoice_lines l WHERE l.store_id=d.store_id AND l.document_id=d.id AND l.quantity>COALESCE((SELECT SUM(quantity) FROM return_lines r WHERE r.store_id=l.store_id AND r.original_line_id=l.id),0)) AND (d.code LIKE ? OR c.name LIKE ?) ORDER BY d.issued_at DESC LIMIT 100",
      [storeId, '%${search.trim()}%', '%${search.trim()}%'],
    );
  }

  Future<List<Map<String, Object?>>> returnableLines(String documentId) {
    require(Permission.returns);
    return db.rows(
      'SELECT l.*,v.product_id,COALESCE((SELECT SUM(quantity) FROM return_lines r WHERE r.store_id=l.store_id AND r.original_line_id=l.id),0) AS returned FROM invoice_lines l JOIN product_variants v ON v.id=l.variant_id WHERE l.store_id=? AND l.document_id=? ORDER BY l.id',
      [storeId, documentId],
    );
  }

  Future<ReturnQuote> quoteReturn({
    required String originalId,
    required List<ReturnSelection> items,
    List<ReplacementSelection> replacements = const [],
    int received = 0,
    bool voidOriginal = false,
  }) async {
    require(Permission.returns);
    if (voidOriginal) {
      require(Permission.voidInvoice);
    }
    if (items.isEmpty ||
        items.length > 48 ||
        items.map((i) => i.lineId).toSet().length != items.length) {
      throw ArgumentError('Chọn từ 1 đến 48 dòng nhận lại, không lặp dòng.');
    }
    final rows = await db.rows(
      "SELECT * FROM documents WHERE store_id=? AND id=? AND ((type='HD' AND kind='sale') OR (type='DT' AND kind IN ('return','exchange')))",
      [storeId, originalId],
    );
    if (rows.isEmpty || rows.single['device_id'] != deviceId) {
      throw StateError('Đổi/trả offline dùng máy đã lập chứng từ gốc.');
    }
    if ((await db.rows(
      "SELECT id FROM document_events WHERE store_id=? AND document_id=? AND type='CANCELLED'",
      [storeId, originalId],
    )).isNotEmpty) {
      throw StateError('Chứng từ đã hủy.');
    }
    final original = rows.single;
    if (voidOriginal && (original['type'] != 'HD' || replacements.isNotEmpty)) {
      throw StateError('Hủy HD không kèm hàng thay thế.');
    }
    if (clock().isBefore(DateTime.parse(original['issued_at'] as String))) {
      throw StateError('Đồng hồ đang trước ngày chứng từ gốc.');
    }
    final allLines = await returnableLines(originalId),
        sources = <String, ReturnedItem>{},
        returned = <Map<String, Object?>>[],
        inStock = <String, int>{};
    var creditTotal = BigInt.zero;
    for (final item in items) {
      final line = allLines.where((l) => l['id'] == item.lineId).firstOrNull;
      if (line == null) {
        throw StateError('Dòng hàng không thuộc chứng từ gốc.');
      }
      final net = checkedMoney(
            BigInt.from(line['unit_price'] as int) *
                    BigInt.from(line['quantity'] as int) -
                BigInt.from(line['discount'] as int),
          ),
          credit = returnCredit(
            net,
            line['quantity'] as int,
            line['returned'] as int,
            item.quantity,
          );
      line['return_quantity'] = item.quantity;
      line['credit'] = credit;
      line['base_returned'] = line['returned'];
      returned.add(line);
      creditTotal += BigInt.from(credit);
      sources[item.lineId] = ReturnedItem(
        productId: line['product_id'] as String,
        quantity: item.quantity,
        credit: credit,
      );
      inStock.update(
        line['variant_id'] as String,
        (q) => q + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    if (voidOriginal) {
      final remaining = allLines
          .where((l) => (l['quantity'] as int) > (l['returned'] as int))
          .toList();
      if (remaining.length != items.length ||
          remaining.any(
            (l) =>
                sources[l['id']]?.quantity !=
                (l['quantity'] as int) - (l['returned'] as int),
          )) {
        throw StateError('Hủy cần nhận lại toàn bộ số món còn lại.');
      }
    }
    final variants = <String, Map<String, Object?>>{};
    for (final group in replacements) {
      if (variants.containsKey(group.variantId)) {
        continue;
      }
      final list = await db.rows(
        'SELECT v.*,p.name,p.school_year FROM product_variants v JOIN products p ON p.id=v.product_id WHERE v.id=? AND v.active=1 AND p.active=1',
        [group.variantId],
      );
      if (list.isEmpty) {
        throw StateError('Hàng thay thế đã ngừng bán.');
      }
      variants[group.variantId] = list.single;
    }
    final plan = priceReplacements(replacements, sources, {
      for (final e in variants.entries)
        e.key: ReplacementVariant(
          e.value['product_id'] as String,
          e.value['price'] as int,
        ),
    });
    for (final e in plan.entries) {
      final allocations = await db.rows(
        'SELECT quantity FROM device_stock_allocations WHERE store_id=? AND device_id=? AND variant_id=?',
        [storeId, deviceId, e.key],
      );
      final available =
          (allocations.firstOrNull?['quantity'] as int? ?? 0) -
          await reservedQuantity(e.key) +
          (inStock[e.key] ?? 0);
      if (available < e.value.quantity) {
        throw StateError('Không đủ lượng hàng thay thế được phân bổ cho máy.');
      }
    }
    final returnedValue = checkedMoney(creditTotal),
        replacementValue = checkedMoney(
          plan.values.fold(BigInt.zero, (n, p) => n + BigInt.from(p.amount)),
        ),
        balance =
            (await db.rows(
                  'SELECT COALESCE(SUM(amount),0) AS balance FROM receivable_ledger WHERE store_id=? AND document_id=?',
                  [storeId, originalId],
                )).single['balance']
                as int;
    return ReturnQuote(
      original,
      returned,
      variants,
      plan,
      returnedValue,
      replacementValue,
      settleReturn(balance, returnedValue, replacementValue, received),
    );
  }

  Future<ReturnResult> createReturn({
    required String originalId,
    required List<ReturnSelection> items,
    List<ReplacementSelection> replacements = const [],
    required String reason,
    required int received,
    required String method,
    String customerName = '',
    String phone = '',
    bool voidOriginal = false,
    String? commandId,
    int? expectedCashDue,
  }) async {
    final actor = require(Permission.returns);
    if (voidOriginal) {
      require(Permission.voidInvoice);
    }
    if (reason.trim().isEmpty ||
        reason.length > 200 ||
        !['cash', 'bank'].contains(method)) {
      throw ArgumentError(
        'Nhập lý do tối đa 200 ký tự và phương thức thanh toán.',
      );
    }
    final id = commandId ?? uuid.v7(),
        hash = sha256
            .convert(
              utf8.encode(
                jsonEncode({
                  'original': originalId,
                  'items': items.map((i) => i.toJson()).toList(),
                  'replacements': replacements.map((r) => r.toJson()).toList(),
                  'reason': reason.trim(),
                  'received': received,
                  'method': method,
                  'customer_name': customerName,
                  'phone': phone,
                  'void': voidOriginal,
                  'expected_cash_due': expectedCashDue,
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
        if (d['type'] != 'DT' || m['command_hash'] != hash) {
          throw StateError('ID đổi/trả đã dùng với nội dung khác.');
        }
        return ReturnResult(
          id,
          d['code'] as String,
          ReturnSettlement(
            m['debt_offset'] as int,
            m['cash_due'] as int,
            m['refund'] as int,
            m['received'] as int,
            m['new_debt'] as int,
            m['total'] as int,
          ),
        );
      }
      final q = await quoteReturn(
            originalId: originalId,
            items: items,
            replacements: replacements,
            received: received,
            voidOriginal: voidOriginal,
          ),
          s = q.settlement;
      if (expectedCashDue != null && s.cashDue != expectedCashDue) {
        throw StateError(
          'Giá trị đổi/trả hoặc công nợ đã thay đổi. Kiểm tra lại.',
        );
      }
      final oldMeta = jsonDecode(q.original['metadata_json'] as String) as Map;
      String? customer = q.original['customer_id'] as String?;
      var newCustomer = false;
      var name = customerName.trim(), contact = phone.trim();
      if (customer != null) {
        final c = (await db.rows(
          'SELECT name,phone FROM customers WHERE store_id=? AND id=?',
          [storeId, customer],
        )).single;
        name = c['name'] as String;
        contact = c['phone'] as String;
      }
      if (s.newDebt > 0 && name.isEmpty) {
        throw StateError('Đổi hàng còn nợ cần tên khách hàng.');
      }
      if (name.length > 200) {
        throw ArgumentError('Tên khách tối đa 200 ký tự.');
      }
      final time = now;
      if (customer == null && name.isNotEmpty) {
        customer = uuid.v7();
        newCustomer = true;
        await db.execute(
          "INSERT INTO customers(id,store_id,name,phone,kind,updated_at) VALUES (?,?,?,?,'parent',?)",
          [customer, storeId, name, contact, time],
        );
      }
      final code = await allocateDocumentCode(
        'DT',
        issuedAt: DateTime.parse(time),
      );
      final metadata = {
        for (final key in [
          'school_id',
          'school_name',
          'student_id',
          'student_name',
          'class_name',
          'academic_year',
        ])
          if (oldMeta.containsKey(key)) key: oldMeta[key],
        'original_code': q.original['code'],
        'reason': reason.trim(),
        'void_original': voidOriginal,
        'replacements': replacements.map((r) => r.toJson()).toList(),
        'returned_value': q.returnedValue,
        'replacement_value': q.replacementValue,
        'debt_offset': s.offset,
        'cash_due': s.cashDue,
        'refund': s.refund,
        'received': s.received,
        'new_debt': s.newDebt,
        'total': s.total,
        'customer_name': name,
        'phone': contact,
        'new_customer': newCustomer,
        'command_hash': hash,
      };
      await db.execute(
        'INSERT INTO documents VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          'DT',
          replacements.isEmpty ? 'return' : 'exchange',
          code,
          time,
          actor.userId,
          customer,
          originalId,
          s.total,
          0,
          s.total,
          q.original['school_year'],
          jsonEncode(metadata),
        ],
      );
      for (final line in q.returned) {
        await db.execute('INSERT INTO return_lines VALUES (?,?,?,?,?,?,?)', [
          uuid.v7(),
          storeId,
          id,
          line['id'],
          line['return_quantity'],
          line['credit'],
          line['base_returned'],
        ]);
      }
      for (final e in q.replacements.entries) {
        final v = q.variants[e.key]!, p = e.value;
        await db.execute(
          'INSERT INTO invoice_lines VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            id,
            e.key,
            v['name'],
            v['size'],
            v['color'],
            v['unit'],
            p.quantity,
            p.unitPrice,
            v['cost'],
            p.discount,
            v['lww_key'],
          ],
        );
      }
      final inStock = <String, int>{};
      for (final line in q.returned) {
        inStock.update(
          line['variant_id'] as String,
          (n) => n + (line['return_quantity'] as int),
          ifAbsent: () => line['return_quantity'] as int,
        );
      }
      for (final e in inStock.entries) {
        await db.execute(
          'INSERT INTO stock_movements VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            deviceId,
            e.key,
            e.value,
            'return',
            id,
            'Nhận lại $code',
            actor.userId,
            time,
          ],
        );
      }
      for (final e in q.replacements.entries) {
        await db.execute(
          'INSERT INTO stock_movements VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            deviceId,
            e.key,
            -e.value.quantity,
            'sale',
            id,
            'Thay thế $code',
            actor.userId,
            time,
          ],
        );
      }
      final cash = s.refund > 0 ? s.refund : s.received;
      if (cash > 0) {
        await db.execute('INSERT INTO payments VALUES (?,?,?,?,?,?,?,?,?,?)', [
          uuid.v7(),
          storeId,
          deviceId,
          id,
          actor.userId,
          cash,
          method,
          s.refund > 0 ? 'refund' : 'receive',
          time,
          reason.trim(),
        ]);
      }
      if (s.offset > 0) {
        await db.execute(
          'INSERT INTO receivable_adjustments VALUES (?,?,?,?,?,?,?)',
          [uuid.v7(), storeId, customer, originalId, id, -s.offset, time],
        );
      }
      if (s.newDebt > 0) {
        await db.execute(
          'INSERT INTO receivable_entries VALUES (?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            customer,
            id,
            null,
            s.newDebt,
            DateTime.parse(time)
                .add(const Duration(days: 30, hours: 7))
                .toIso8601String()
                .substring(0, 10),
            time,
          ],
        );
      }
      if (voidOriginal) {
        await db.execute(
          'INSERT INTO document_events VALUES (?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            originalId,
            'CANCELLED',
            id,
            reason.trim(),
            actor.userId,
            time,
          ],
        );
      }
      await audit(
        voidOriginal ? 'INVOICE_VOID' : 'RETURN_CREATE',
        'document',
        id,
        reason: reason.trim(),
        severity: 'critical',
        changes: {
          'original_id': originalId,
          'returned_value': q.returnedValue,
          'replacement_value': q.replacementValue,
          'debt_offset': s.offset,
          'received': s.received,
          'refund': s.refund,
          'new_debt': s.newDebt,
        },
      );
      await enqueue('return', {
        'id': id,
        'original_id': originalId,
        'new_customer': newCustomer,
      }, 0);
      return ReturnResult(id, code, s);
    });
  }

  Future<List<Map<String, Object?>>> returnsHistory() {
    require(Permission.returns);
    return db.rows(
      "SELECT * FROM documents WHERE store_id=? AND type='DT' ORDER BY issued_at DESC LIMIT 300",
      [storeId],
    );
  }
}
