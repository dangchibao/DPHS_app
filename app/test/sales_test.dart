import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalService service;
  setUp(() async {
    service = await salesFixture();
  });
  tearDown(() async {
    await service.db.close();
  });
  test('Bán hàng nguyên tử, snapshot, tiền thừa, mã chứng từ', () async {
    final sale = await service.sell(
      items: [const CartItem('v1', 2)],
      discount: 10000,
      received: 200000,
      method: 'cash',
    );
    expect(sale.code, 'HD-CN01-A2-20261115-001');
    expect(sale.total, 190000);
    expect(sale.change, 10000);
    expect(
      (await service.db.rows('SELECT quantity FROM stock_balances'))
          .single['quantity'],
      8,
    );
    expect(
      (await service.db.rows('SELECT amount FROM payments')).single['amount'],
      190000,
    );
    await service.db.execute(
      "UPDATE product_variants SET price=999999,lww_key='2026-11-15T12:00:00.000Z|A2|new-price' WHERE id='v1'",
    );
    expect(
      (await service.db.rows('SELECT unit_price FROM invoice_lines'))
          .single['unit_price'],
      100000,
    );
  });
  test('Mô phỏng mất điện trước commit không mất tồn/counter', () async {
    await expectLater(
      service.db.transaction(() async {
        await service.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 100000,
          method: 'cash',
        );
        throw StateError('Mất điện trước commit');
      }),
      throwsStateError,
    );
    expect(await service.db.rows('SELECT * FROM documents'), isEmpty);
    expect(await service.db.rows('SELECT * FROM document_counters'), isEmpty);
    expect(
      (await service.db.rows('SELECT quantity FROM stock_balances'))
          .single['quantity'],
      10,
    );
    final sale = await service.sell(
      items: [const CartItem('v1', 1)],
      discount: 0,
      received: 100000,
      method: 'cash',
    );
    expect(sale.code.endsWith('-001'), true);
  });
  test(
    'Retry sau commit không tạo thêm hóa đơn, khác nội dung bị chặn',
    () async {
      final first = await service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 200000,
        method: 'cash',
        commandId: 'sale-retry',
      );
      final again = await service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 200000,
        method: 'cash',
        commandId: 'sale-retry',
      );
      expect(again.code, first.code);
      expect(again.change, 100000);
      expect((await service.db.rows('SELECT * FROM documents')).length, 1);
      await expectLater(
        service.sell(
          items: [const CartItem('v1', 2)],
          discount: 0,
          received: 200000,
          method: 'cash',
          commandId: 'sale-retry',
        ),
        throwsStateError,
      );
    },
  );
  test('Hai thiết bị offline cùng ngày không trùng mã', () async {
    await service.db.execute(
      "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('device-b2','store-cn01','B2','Máy B2','approved','2026-11-15')",
    );
    final other = LocalService(
      service.db,
      deviceId: 'device-b2',
      clock: service.clock,
    );
    final first = await service.db.transaction(
      () => service.allocateDocumentCode('HD'),
    );
    final second = await service.db.transaction(
      () => other.allocateDocumentCode('HD'),
    );
    expect(first, 'HD-CN01-A2-20261115-001');
    expect(second, 'HD-CN01-B2-20261115-001');
  });
  test('Đặt cọc tạo nợ đúng; thiếu tên khách không tạo chứng từ', () async {
    await expectLater(
      service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 30000,
        method: 'bank',
      ),
      throwsStateError,
    );
    final sale = await service.sell(
      items: [const CartItem('v1', 1)],
      discount: 0,
      received: 30000,
      method: 'bank',
      customerName: 'Phụ huynh thử',
    );
    expect(sale.code.endsWith('-001'), true);
    expect(
      (await service.db.rows('SELECT amount FROM receivable_entries'))
          .single['amount'],
      70000,
    );
  });
  test(
    'Hóa đơn/dòng/thanh toán bất biến; xuất vượt tồn rollback toàn bộ',
    () async {
      await expectLater(
        service.sell(
          items: [const CartItem('v1', 11)],
          discount: 0,
          received: 1100000,
          method: 'cash',
        ),
        throwsA(anything),
      );
      expect(await service.db.rows('SELECT * FROM documents'), isEmpty);
      await service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 100000,
        method: 'cash',
      );
      for (final table in ['documents', 'invoice_lines', 'payments']) {
        await expectLater(
          service.db.execute('DELETE FROM $table'),
          throwsA(anything),
        );
      }
    },
  );
  test('Phân bổ giảm giá không mất 1 đồng, dùng số nguyên lớn an toàn', () {
    expect(allocateMoney(101, [1, 1, 1]), [34, 34, 33]);
    expect(allocateMoney(0, [0, 0]), [0, 0]);
    final result = allocateMoney(999999999999, [8000000000000, 9000000000000]);
    expect(result.fold(0, (a, b) => a + b), 999999999999);
  });
}
