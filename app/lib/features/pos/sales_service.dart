import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart';

import '../../core/local_service.dart';
import '../../core/money.dart';
export '../../core/money.dart' show allocateMoney;
import '../../core/auth/permissions.dart';
import '../schools/school_service.dart';
import '../catalog/combo_service.dart';
import 'pricing.dart';
import '../pricing/commercial_service.dart';
import '../reservations/reservation_service.dart';

class CartItem {
  const CartItem(this.variantId, this.quantity, {this.expectedPrice});
  final String variantId;
  final int quantity;
  final int? expectedPrice;
}

class SaleResult {
  const SaleResult(this.id, this.code, this.total, this.paid, this.change);
  final String id, code;
  final int total, paid, change;
}

extension SalesService on LocalService {
  Future<String> allocateDocumentCode(String type, {DateTime? issuedAt}) async {
    if (!['HD', 'MR', 'DH', 'DT', 'CK'].contains(type)) {
      throw ArgumentError('Loại chứng từ không hợp lệ.');
    }
    final day = DateFormat('yyyyMMdd')
        .format((issuedAt ?? clock()).toUtc().add(const Duration(hours: 7)));
    final store =
        (await db.rows('SELECT code FROM stores WHERE id=?', [
              storeId,
            ])).single['code']
            as String;
    final device =
        (await db.rows('SELECT code FROM devices WHERE store_id=? AND id=?', [
              storeId,
              deviceId,
            ])).single['code']
            as String;
    await db.execute(
      'INSERT INTO document_counters VALUES (?,?,?,?,1) ON CONFLICT(store_id,device_id,type,day) DO UPDATE SET value=value+1',
      [storeId, deviceId, type, day],
    );
    final count =
        (await db.rows(
              'SELECT value FROM document_counters WHERE store_id=? AND device_id=? AND type=? AND day=?',
              [storeId, deviceId, type, day],
            )).single['value']
            as int;
    return '$type-${store.replaceFirst('NT-', '')}-$device-$day-${count.toString().padLeft(3, '0')}';
  }

  Future<SaleResult> sell({
    required List<CartItem> items,
    required int discount,
    required int received,
    required String method,
    String customerName = '',
    String phone = '',
    String? commandId,
    String? heldCartId,
    String? schoolId,
    String? studentId,
    String? customerId,
    List<ComboSelection> combos = const [],
    String? priceListId,
    String? promotionId,
    String voucher = '',
    int? expectedTotal,
    String? reservationId,
  }) async {
    final actor = require(Permission.sell);
    if (items.isEmpty ||
        items.any((e) => e.quantity <= 0 || e.quantity > 100000) ||
        !['cash', 'bank'].contains(method) ||
        discount < 0 ||
        received < 0) {
      throw ArgumentError('Giỏ hàng hoặc thanh toán không hợp lệ.');
    }
    final id = commandId ?? uuid.v7();
    final requestHash = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'items': [
                for (final i in items)
                  {'variant': i.variantId, 'quantity': i.quantity},
              ],
              'discount': discount,
              'received': received,
              'method': method,
              'customer': customerName,
              'phone': phone,
              'school_id': schoolId,
              'student_id': studentId,
              'customer_id': customerId,
              'combos': combos.map((g) => g.toProof()).toList(),
              'held_cart_id': heldCartId,
              'price_list_id': priceListId,
              'promotion_id': promotionId,
              'voucher': voucher.trim().toUpperCase(),
              'expected_total': expectedTotal,
              'reservation_id': reservationId,
            }),
          ),
        )
        .toString();
    return db.transaction(() async {
      final duplicate = await db.rows(
        'SELECT * FROM documents WHERE store_id=? AND id=?',
        [storeId, id],
      );
      if (duplicate.isNotEmpty) {
        final d = duplicate.single,
            metadata = jsonDecode(d['metadata_json'] as String) as Map;
        if (metadata['command_hash'] != requestHash) {
          throw StateError('ID thanh toán đã dùng với nội dung khác.');
        }
        return SaleResult(
          id,
          d['code'] as String,
          d['total'] as int,
          metadata['paid'] as int,
          metadata['change'] as int,
        );
      }
      if (heldCartId != null) {
        final draft = await db.rows(
          'SELECT id FROM held_carts WHERE store_id=? AND id=?',
          [storeId, heldCartId],
        );
        final finalized = await db.rows(
          "SELECT id FROM documents WHERE store_id=? AND type='HD' AND kind='sale' AND json_extract(metadata_json,'\$.held_cart_id')=?",
          [storeId, heldCartId],
        );
        if (draft.isEmpty || finalized.isNotEmpty) {
          throw StateError(
            'Đơn tạm không còn hoặc đã thanh toán. Vui lòng tải lại danh sách.',
          );
        }
      }
      final quantities = <String, int>{};
      for (final item in items) {
        quantities.update(
          item.variantId,
          (n) => n + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
      final variants = <Map<String, Object?>>[];
      Map<String, Object?>? reservation;
      if (reservationId != null) {
        reservation = await activeReservation(reservationId);
        final held = await db.rows(
          'SELECT variant_id,quantity FROM reservation_lines WHERE store_id=? AND document_id=?',
          [storeId, reservationId],
        );
        for (final line in held) {
          if ((quantities[line['variant_id']] ?? 0) <
              (line['quantity'] as int)) {
            throw StateError('Cần giao đủ các món đã giữ.');
          }
        }
        if (customerId != null && customerId != reservation['customer_id']) {
          throw StateError('Khách nhận khác phiếu giữ hàng.');
        }
      }
      for (final entry in quantities.entries) {
        final rows = await db.rows(
          '''SELECT v.*,p.name,p.school_year,COALESCE(s.price_override,v.price) AS sale_price FROM product_variants v JOIN products p ON p.id=v.product_id LEFT JOIN store_variant_settings s ON s.variant_id=v.id AND s.store_id=? WHERE v.id=? AND v.active=1 AND p.active=1''',
          [storeId, entry.key],
        );
        if (rows.isEmpty) {
          throw StateError('Sản phẩm đã ngừng bán hoặc không tồn tại.');
        }
        final row = rows.single;
        final expected = items
            .where((e) => e.variantId == entry.key)
            .map((e) => e.expectedPrice)
            .whereType<int>();
        if (expected.any((price) => price != row['sale_price'])) {
          throw StateError(
            'Giá đã thay đổi. Vui lòng tải lại giỏ và kiểm tra trước khi thanh toán.',
          );
        }
        final stock = await db.rows(
          'SELECT quantity FROM device_stock_allocations WHERE store_id=? AND device_id=? AND variant_id=?',
          [storeId, deviceId, entry.key],
        );
        if (stock.isEmpty ||
            await availableQuantity(entry.key, exclude: reservationId) <
                entry.value) {
          throw StateError('Không đủ lượng hàng được phân bổ cho thiết bị.');
        }
        row['quantity'] = entry.value;
        variants.add(row);
      }
      final approved = await approvedCombos(combos);
      final issuedAt = DateTime.fromMillisecondsSinceEpoch(
        clock().millisecondsSinceEpoch,
        isUtc: true,
      );
      final context = await schoolSaleContext(
        schoolId: schoolId,
        studentId: studentId,
        customerId: reservation?['customer_id'] as String? ?? customerId,
      );
      final commercial = await commercialQuote(
        items: variants
            .map(
              (v) => PricedItem(
                id: v['id'] as String,
                productId: v['product_id'] as String,
                price: v['sale_price'] as int,
                quantity: v['quantity'] as int,
              ),
            )
            .toList(),
        combos: approved,
        context: context,
        priceListId: priceListId,
        promotionId: promotionId,
        voucher: voucher,
        manual: discount,
        at: issuedAt,
      );
      final pricing = commercial.price,
          promotional = commercial.promotionDiscount,
          extraDiscount = discount + promotional;
      final gross = variants
          .map((v) => pricing.lines[v['id']]!.amount)
          .toList();
      final subtotal = pricing.subtotal,
          documentDiscount = extraDiscount + pricing.roundingDiscount;
      if (subtotal > 9007199254740991 ||
          extraDiscount > pricing.amount ||
          received > 9007199254740991) {
        throw StateError('Số tiền không hợp lệ.');
      }
      final rules = await db.rows(
        "SELECT value FROM store_settings WHERE store_id=? AND key='cashier_discount_percent'",
        [storeId],
      );
      final maxDiscount = rules.isEmpty
          ? 10
          : int.parse(rules.single['value'] as String);
      if (actor.role == Role.cashier &&
          discount * 100 > pricing.amount * maxDiscount) {
        throw StateError(
          'Giảm giá vượt quyền thu ngân. Cần quản lý thực hiện.',
        );
      }
      final total = pricing.amount - extraDiscount,
          paid = received > total ? total : received;
      if (expectedTotal != null && total != expectedTotal) {
        throw StateError(
          'Giá/ưu đãi đã thay đổi. Kiểm tra lại tổng tiền trước khi thanh toán.',
        );
      }
      final resolvedName =
              context['customer_name'] as String? ?? customerName.trim(),
          resolvedPhone = context['phone'] as String? ?? phone.trim();
      if (paid < total && resolvedName.isEmpty) {
        throw StateError('Đơn còn nợ cần tên khách hàng.');
      }
      final customer =
          context['customer_id'] as String? ??
          (resolvedName.isEmpty ? null : uuid.v7());
      if (customer != null && !context.containsKey('customer_id')) {
        await db.execute(
          'INSERT INTO customers(id,store_id,name,phone,kind,updated_at) VALUES (?,?,?,?,?,?)',
          [customer, storeId, resolvedName, resolvedPhone, 'parent', now],
        );
      }
      final code = await allocateDocumentCode('HD', issuedAt: issuedAt);
      await db.execute(
        'INSERT INTO documents VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          'HD',
          'sale',
          code,
          issuedAt.toIso8601String(),
          actor.userId,
          customer,
          null,
          subtotal,
          documentDiscount,
          total,
          context['academic_year'] ?? variants.first['school_year'],
          jsonEncode({
            ...context,
            'customer_name': resolvedName,
            'phone': resolvedPhone,
            'held_cart_id': heldCartId,
            'reservation_id': reservationId,
            'manual_discount': discount,
            'price_list': commercial.priceList?.proof,
            'promotion': commercial.promotion?.proof,
            'promotion_discount': promotional,
            'voucher': voucher.trim().toUpperCase(),
            'price_list_name': commercial.priceList?.name,
            'promotion_name': commercial.promotion?.name,
            'regular_subtotal': pricing.regularSubtotal,
            'combo_groups': approved.map((g) => g.toProof()).toList(),
            'combo_snapshots': approved
                .map(
                  (g) => {
                    'name': g.rule.name,
                    'price': g.rule.price,
                    'quantity': g.quantity,
                  },
                )
                .toList(),
            'command_hash': requestHash,
            'paid': paid,
            'change': received - paid,
          }),
        ],
      );
      final allocations = allocateMoney(extraDiscount, gross);
      for (var i = 0; i < variants.length; i++) {
        final v = variants[i], quantity = v['quantity'] as int;
        await db.execute(
          'INSERT INTO invoice_lines VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            id,
            v['id'],
            v['name'],
            v['size'],
            v['color'],
            v['unit'],
            quantity,
            pricing.lines[v['id']]!.unitPrice,
            v['cost'],
            allocations[i] + pricing.lines[v['id']]!.roundingDiscount,
            v['lww_key'],
          ],
        );
      }
      if (reservationId != null) {
        await db.execute(
          'INSERT INTO reservation_events VALUES (?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            deviceId,
            reservationId,
            'consume',
            id,
            actor.userId,
            'Giao hàng qua $code',
            issuedAt.toIso8601String(),
          ],
        );
      }
      for (final v in variants) {
        await db.execute(
          'INSERT INTO stock_movements VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            deviceId,
            v['id'],
            -(v['quantity'] as int),
            'sale',
            id,
            'Bán hàng $code',
            actor.userId,
            now,
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
          now,
          'Thanh toán khi bán',
        ]);
      }
      if (paid < total) {
        await db.execute(
          'INSERT INTO receivable_entries VALUES (?,?,?,?,?,?,?,?)',
          [
            uuid.v7(),
            storeId,
            customer,
            id,
            null,
            total - paid,
            DateFormat(
              'yyyy-MM-dd',
            ).format(clock().toUtc().add(const Duration(days: 30, hours: 7))),
            now,
          ],
        );
      }
      await audit(
        'INVOICE_CREATE',
        'document',
        id,
        changes: {
          'code': code,
          'total': total,
          'discount': documentDiscount,
          'manual_discount': discount,
          'combo_savings': pricing.comboSavings,
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
      await enqueue('sale', {'id': id}, 0);
      if (heldCartId != null) {
        await db.execute('DELETE FROM held_carts WHERE store_id=? AND id=?', [
          storeId,
          heldCartId,
        ]);
      }
      return SaleResult(id, code, total, paid, received - paid);
    });
  }

  Future<List<Map<String, Object?>>> invoices() {
    require(Permission.sell);
    return db.rows(
      '''SELECT d.*,COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.store_id=d.store_id AND p.document_id=d.id AND p.direction='receive'),0) AS paid,EXISTS(SELECT 1 FROM document_events e WHERE e.store_id=d.store_id AND e.document_id=d.id AND e.type='CANCELLED') AS cancelled FROM documents d WHERE d.store_id=? AND d.type='HD' ORDER BY d.issued_at DESC LIMIT 300''',
      [storeId],
    );
  }

  Future<void> holdCart(
    List<CartItem> items,
    String name, {
    List<ComboSelection> combos = const [],
    String? existingId,
  }) async {
    final actor = require(Permission.sell);
    if (items.isEmpty) throw StateError('Giỏ hàng đang trống.');
    await db.transaction(() async {
      final id = existingId ?? uuid.v7();
      if (existingId != null &&
          (await db.rows(
            'SELECT id FROM held_carts WHERE store_id=? AND id=?',
            [storeId, id],
          )).isEmpty) {
        throw StateError('Đơn tạm không còn tồn tại.');
      }
      await db.execute(
        'INSERT INTO held_carts VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET user_id=excluded.user_id,name=excluded.name,payload=excluded.payload,created_at=excluded.created_at WHERE held_carts.store_id=excluded.store_id',
        [
          id,
          storeId,
          actor.userId,
          name.trim().isEmpty ? 'Đơn tạm' : name.trim(),
          jsonEncode({
            'items': [
              for (final e in items)
                {'variant_id': e.variantId, 'quantity': e.quantity},
            ],
            'combos': combos.map((g) => g.toJson()).toList(),
          }),
          now,
        ],
      );
      await audit('CART_HOLD', 'held_cart', id);
    });
  }
}
