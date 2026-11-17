import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ngoc_thanh_pos/features/transfers/transfer_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/reservations/reservation_service.dart';

import 'transfer_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'CK xuất giữ snapshot, đang chuyển, nhận thiếu và replay không nhân đôi',
    () async {
      final s = await fixture();
      addTearDown(s.db.close);
      final out = await s.createTransferOut(
        targetDeviceId: 'd2',
        items: [const CartItem('v1', 5)],
        reason: 'Chuyển CN02',
        commandId: 'command-out',
      );
      expect((await s.outgoingTransfers()).single['dispatched'], 0);
      expect(await s.availableQuantity('v1'), 5);
      await s.dispatchTransfer(out.id, 'Giao vận chuyển');
      expect((await s.outgoingTransfers()).single['dispatched'], 1);
      final t = await targetFor(s, out.id);
      await s.db.execute(
        "UPDATE product_variants SET cost=80000,lww_key='new-version' WHERE id='v1'",
      );
      final received = await t.receiveTransfer(
        offerId: out.id,
        quantities: {'v1': 4},
        reason: 'Nhận thiếu một áo',
        commandId: 'command-in',
      );
      final replay = await t.receiveTransfer(
        offerId: out.id,
        quantities: {'v1': 4},
        reason: 'Nhận thiếu một áo',
        commandId: 'command-in',
      );
      expect(replay.id, received.id);
      expect(await t.availableQuantity('v1'), 4);
      expect(await s.availableQuantity('v1'), 5);
      expect(
        (await s.db.rows(
          'SELECT unit_cost FROM invoice_lines WHERE document_id=?',
          [received.id],
        )).single['unit_cost'],
        50000,
      );
      final queue = (await s.db.rows(
        "SELECT payload FROM outbox WHERE entity_type='transfer_in'",
      )).single;
      final records = jsonDecode(queue['payload'] as String) as List;
      expect(
        records.indexWhere((r) => r['table'] == 'transfer_receipts'),
        lessThan(records.indexWhere((r) => r['table'] == 'stock_movements')),
      );
      await expectLater(
        t.receiveTransfer(
          offerId: out.id,
          quantities: {'v1': 4},
          reason: 'Nhận lại',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'Phần giữ bảo vệ xuất CK, restore và vai trò chặn thay đổi kho',
    () async {
      final s = await fixture();
      addTearDown(s.db.close);
      final held = await s.reserveItems(
        [const CartItem('v1', 7)],
        name: 'Phụ huynh',
        duration: const Duration(hours: 2),
      );
      await expectLater(
        s.createTransferOut(
          targetDeviceId: 'd2',
          items: [const CartItem('v1', 5)],
          reason: 'Chuyển',
        ),
        throwsStateError,
      );
      expect(
        await s.db.rows("SELECT id FROM documents WHERE type='CK'"),
        isEmpty,
      );
      expect(
        await s.db.rows("SELECT * FROM document_counters WHERE type='CK'"),
        isEmpty,
      );
      s.restoreBlocked = true;
      await expectLater(
        s.releaseReservation(held, 'Giải phóng'),
        throwsStateError,
      );
      await expectLater(
        s.createTransferOut(
          targetDeviceId: 'd2',
          items: [const CartItem('v1', 1)],
          reason: 'Chuyển',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'Nhận 0 không tạo sổ cái giả; lỗi nhận rollback counter, receipt và stock',
    () async {
      final s = await fixture();
      addTearDown(s.db.close);
      final out = await s.createTransferOut(
        targetDeviceId: 'd2',
        items: [const CartItem('v1', 5)],
        reason: 'Chuyển',
      );
      await s.dispatchTransfer(out.id, 'Giao');
      final t = await targetFor(s, out.id);
      await s.db.execute(
        "CREATE TRIGGER fail_receipt BEFORE INSERT ON transfer_receipts BEGIN SELECT RAISE(ABORT,'INJECTED'); END;",
      );
      await expectLater(
        t.receiveTransfer(
          offerId: out.id,
          quantities: {'v1': 0},
          reason: 'Không có kiện hàng',
        ),
        throwsA(anything),
      );
      expect(
        await s.db.rows("SELECT * FROM documents WHERE store_id='s2'"),
        isEmpty,
      );
      expect(
        await s.db.rows("SELECT * FROM document_counters WHERE store_id='s2'"),
        isEmpty,
      );
      await s.db.execute('DROP TRIGGER fail_receipt');
      final receipt = await t.receiveTransfer(
        offerId: out.id,
        quantities: {'v1': 0},
        reason: 'Không có kiện hàng',
      );
      expect(receipt.code, endsWith('-001'));
      expect(await t.availableQuantity('v1'), 0);
      expect(
        await s.db.rows("SELECT * FROM stock_movements WHERE store_id='s2'"),
        isEmpty,
      );
      expect((await s.db.rows('SELECT * FROM transfer_receipts')).length, 1);
    },
  );
}
