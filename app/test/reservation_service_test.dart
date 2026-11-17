import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/reservations/reservation_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Lỗi xuất kho rollback cả HD, consume, tiền, audit và bộ đếm', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    final dh = await s.reserveItems(
      [const CartItem('v1', 7)],
      name: 'Khách',
      duration: const Duration(hours: 2),
    );
    await s.db.execute(
      "CREATE TRIGGER injected_failure BEFORE INSERT ON stock_movements WHEN NEW.kind='sale' BEGIN SELECT RAISE(ABORT,'INJECTED'); END;",
    );
    await expectLater(
      s.sell(
        items: [const CartItem('v1', 7)],
        discount: 0,
        received: 700000,
        method: 'cash',
        reservationId: dh,
      ),
      throwsA(anything),
    );
    expect(await s.db.rows("SELECT * FROM documents WHERE type='HD'"), isEmpty);
    expect(await s.db.rows('SELECT * FROM reservation_events'), isEmpty);
    expect(await s.db.rows('SELECT * FROM payments'), isEmpty);
    expect(
      await s.db.rows("SELECT * FROM document_counters WHERE type='HD'"),
      isEmpty,
    );
    expect(await s.availableQuantity('v1'), 3);
    await s.db.execute('DROP TRIGGER injected_failure');
    final hd = await s.sell(
      items: [const CartItem('v1', 7)],
      discount: 0,
      received: 700000,
      method: 'cash',
      reservationId: dh,
    );
    expect(hd.code, endsWith('-001'));
  });
  test(
    'Hết hạn cho bán thường, chặn giao DH hết hạn và thời hạn ngoài giới hạn',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      await expectLater(
        s.reserveItems(
          [const CartItem('v1', 1)],
          name: 'Khách',
          duration: const Duration(days: 30, hours: 1),
        ),
        throwsArgumentError,
      );
      final dh = await s.reserveItems(
        [const CartItem('v1', 7)],
        name: 'Khách',
        duration: const Duration(hours: 2),
      );
      final later = LocalService(
        s.db,
        clock: () => DateTime.utc(2026, 11, 15, 3),
      )..session = s.session;
      await expectLater(
        later.sell(
          items: [const CartItem('v1', 7)],
          discount: 0,
          received: 700000,
          method: 'cash',
          reservationId: dh,
        ),
        throwsStateError,
      );
      await later.sell(
        items: [const CartItem('v1', 10)],
        discount: 0,
        received: 1000000,
        method: 'cash',
      );
      expect(await later.availableQuantity('v1'), 0);
    },
  );
  test('Giữ hàng bảo vệ tồn khả dụng, giải phóng không tạo kho giả', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    final id = await s.reserveItems(
      [const CartItem('v1', 7)],
      name: 'Phụ huynh',
      duration: const Duration(hours: 2),
    );
    expect(await s.availableQuantity('v1'), 3);
    expect(
      (await s.db.rows('SELECT quantity FROM stock_balances'))
          .single['quantity'],
      10,
    );
    await expectLater(
      s.sell(
        items: [const CartItem('v1', 4)],
        discount: 0,
        received: 400000,
        method: 'cash',
      ),
      throwsStateError,
    );
    await expectLater(s.adjustStock('v1', -4, 'Kiểm kê'), throwsA(anything));
    await s.releaseReservation(id, 'Khách hủy giữ');
    expect(await s.availableQuantity('v1'), 10);
    expect(
      (await s.db.rows('SELECT COUNT(*) AS n FROM stock_movements'))
          .single['n'],
      1,
    );
    await expectLater(s.releaseReservation(id, 'Lặp'), throwsStateError);
  });
  test(
    'Hết hạn theo clock; sự kiện tương lai không giải phóng tồn quá khứ',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      final id = await s.reserveItems(
        [const CartItem('v1', 7)],
        name: 'Khách',
        duration: const Duration(hours: 2),
      );
      final later = LocalService(
        s.db,
        clock: () => DateTime.utc(2026, 11, 15, 1),
      )..session = s.session;
      await later.releaseReservation(id, 'Giải phóng');
      expect(await s.availableQuantity('v1'), 3);
      expect(await later.availableQuantity('v1'), 10);
      final expired = LocalService(
        s.db,
        clock: () => DateTime.utc(2026, 11, 15, 3),
      )..session = s.session;
      expect(await expired.availableQuantity('v1'), 10);
    },
  );
  test(
    'Giao đủ DH qua HD atomic; replay không nhân đôi; outbox có thứ tự',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      final id = await s.reserveItems(
        [const CartItem('v1', 7)],
        name: 'Khách',
        duration: const Duration(hours: 2),
      );
      await expectLater(
        s.sell(
          items: [const CartItem('v1', 6)],
          discount: 0,
          received: 600000,
          method: 'cash',
          reservationId: id,
        ),
        throwsStateError,
      );
      final hd = await s.sell(
        items: [const CartItem('v1', 8)],
        discount: 0,
        received: 800000,
        method: 'cash',
        reservationId: id,
        commandId: 'command-one',
      );
      final again = await s.sell(
        items: [const CartItem('v1', 8)],
        discount: 0,
        received: 800000,
        method: 'cash',
        reservationId: id,
        commandId: 'command-one',
      );
      expect(again.id, hd.id);
      expect(await s.availableQuantity('v1'), 2);
      expect((await s.db.rows('SELECT * FROM reservation_events')).length, 1);
      expect(
        (await s.db.rows("SELECT value FROM document_counters WHERE type='HD'"))
            .single['value'],
        1,
      );
      final outbox = await s.db.rows(
        "SELECT * FROM outbox WHERE entity_type IN ('reservation','sale') ORDER BY rowid",
      );
      expect(
        jsonDecode(outbox.last['dependencies_json'] as String),
        contains(outbox.first['id']),
      );
      final records = jsonDecode(outbox.last['payload'] as String) as List;
      expect(
        records.indexWhere((r) => r['table'] == 'reservation_events'),
        lessThan(records.indexWhere((r) => r['table'] == 'stock_movements')),
      );
    },
  );
}
