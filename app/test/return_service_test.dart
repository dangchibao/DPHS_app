import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/returns/return_pricing.dart';
import 'package:ngoc_thanh_pos/features/returns/return_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';
import 'package:ngoc_thanh_pos/features/debt/debt_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Lỗi giữa transaction không để lại DT, kho, cấn nợ hoặc nhảy counter',
    () async {
      final s = await salesFixture();
      try {
        final sale = await s.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 40000,
          method: 'cash',
          customerName: 'Phụ huynh',
        );
        final line = (await s.returnableLines(sale.id)).single['id'] as String;
        await s.db.execute(
          "CREATE TRIGGER injected_return_failure BEFORE INSERT ON stock_movements WHEN NEW.kind='return' BEGIN SELECT RAISE(ABORT,'injected_failure'); END;",
        );
        await expectLater(
          s.createReturn(
            originalId: sale.id,
            items: [ReturnSelection(line, 1)],
            reason: 'Trả hàng',
            received: 0,
            method: 'cash',
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          await s.db.rows("SELECT * FROM documents WHERE type='DT'"),
          isEmpty,
        );
        expect(await s.db.rows('SELECT * FROM return_lines'), isEmpty);
        expect(
          await s.db.rows('SELECT * FROM receivable_adjustments'),
          isEmpty,
        );
        expect((await s.debts()).single['balance'], 60000);
        await s.db.execute('DROP TRIGGER injected_return_failure');
        final result = await s.createReturn(
          originalId: sale.id,
          items: [ReturnSelection(line, 1)],
          reason: 'Trả hàng',
          received: 0,
          method: 'cash',
        );
        expect(result.code, 'DT-CN01-A2-20261115-001');
      } finally {
        await s.db.close();
      }
    },
  );
  test('Trả từng phần giữ đúng ưu đãi và hoàn đúng tổng, retry không cộng kho hai lần', () async {
    final s = await salesFixture();
    try {
      final sale = await s.sell(
        items: [const CartItem('v1', 3)],
        discount: 199999,
        received: 100001,
        method: 'cash',
      );
      final line = (await s.returnableLines(sale.id)).single['id'] as String;
      for (var i = 0; i < 3; i++) {
        final result = await s.createReturn(
          originalId: sale.id,
          items: [ReturnSelection(line, 1)],
          reason: 'Trả hàng',
          received: 0,
          method: 'cash',
          commandId: 'return-$i',
        );
        expect(result.settlement.refund, [33333, 33334, 33334][i]);
        final retry = await s.createReturn(
          originalId: sale.id,
          items: [ReturnSelection(line, 1)],
          reason: 'Trả hàng',
          received: 0,
          method: 'cash',
          commandId: 'return-$i',
        );
        expect(retry.code, result.code);
      }
      expect(
        (await s.db.rows('SELECT quantity FROM stock_balances'))
            .single['quantity'],
        10,
      );
      expect(
        (await s.db.rows('SELECT SUM(credit) AS credit FROM return_lines'))
            .single['credit'],
        100001,
      );
      await expectLater(
        s.createReturn(
          originalId: sale.id,
          items: [ReturnSelection(line, 1)],
          reason: 'Trả vượt',
          received: 0,
          method: 'cash',
        ),
        throwsStateError,
      );
      expect(
        (await s.db.rows("SELECT * FROM documents WHERE type='DT'")).length,
        3,
      );
    } finally {
      await s.db.close();
    }
  });
  test('Cấn nợ thật thay vì tạo thu tiền giả, chặn thu thêm sau khi trả hết', () async {
    final s = await salesFixture();
    try {
      final sale = await s.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 40000,
        method: 'cash',
        customerName: 'Phụ huynh',
      );
      final line = (await s.returnableLines(sale.id)).single['id'] as String;
      final result = await s.createReturn(
        originalId: sale.id,
        items: [ReturnSelection(line, 1)],
        reason: 'Trả do không vừa',
        received: 0,
        method: 'bank',
      );
      expect(result.settlement.offset, 60000);
      expect(result.settlement.refund, 40000);
      expect(await s.debts(), isEmpty);
      expect(
        (await s.db.rows(
          "SELECT SUM(amount) AS paid FROM payments WHERE direction='receive'",
        )).single['paid'],
        40000,
      );
      expect(
        (await s.db.rows('SELECT amount FROM receivable_adjustments'))
            .single['amount'],
        -60000,
      );
      await expectLater(
        s.collectDebt(
          documentId: sale.id,
          amount: 1,
          method: 'cash',
          note: 'Thu vượt',
        ),
        throwsStateError,
      );
      final jobs = await s.db.rows(
        "SELECT * FROM outbox WHERE entity_type='return'",
      );
      expect(jobs.length, 1);
    } finally {
      await s.db.close();
    }
  });
  test(
    'Đổi size giữ giá cũ; món thay thế có thể trả tiếp mà không hoàn trùng',
    () async {
      final s = await salesFixture();
      try {
        await s.db.execute(
          "INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at,lww_key) VALUES ('v2','p1','SKU-L','L','Trắng','cái',50000,150000,'2026-11-15','v2-price')",
        );
        await s.adjustStock('v2', 5, 'Nhập size L');
        final sale = await s.sell(
          items: [const CartItem('v1', 3)],
          discount: 199999,
          received: 100001,
          method: 'cash',
        );
        final line = (await s.returnableLines(sale.id)).single['id'] as String;
        final exchanged = await s.createReturn(
          originalId: sale.id,
          items: [ReturnSelection(line, 3)],
          replacements: [ReplacementSelection('v2', 3, sourceLineId: line)],
          reason: 'Đổi size L',
          received: 0,
          method: 'cash',
        );
        expect(exchanged.settlement.cashDue, 0);
        final newLine = (await s.returnableLines(exchanged.id)).single;
        expect(newLine['unit_price'], 33334);
        expect(newLine['discount'], 1);
        final returned = await s.createReturn(
          originalId: exchanged.id,
          items: [ReturnSelection(newLine['id'] as String, 3)],
          reason: 'Trả món đổi',
          received: 0,
          method: 'cash',
        );
        expect(returned.settlement.refund, 100001);
        expect(
          (await s.db.rows(
            "SELECT quantity FROM stock_balances WHERE variant_id='v2'",
          )).single['quantity'],
          5,
        );
        expect(
          (await s.db.rows(
            "SELECT quantity FROM stock_balances WHERE variant_id='v1'",
          )).single['quantity'],
          10,
        );
      } finally {
        await s.db.close();
      }
    },
  );
  test(
    'Hủy HD cần quyền riêng, ghi DT và sự kiện mới, hóa đơn gốc còn nguyên',
    () async {
      final s = await salesFixture();
      try {
        final sale = await s.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 100000,
          method: 'cash',
        );
        final line = (await s.returnableLines(sale.id)).single['id'] as String,
            owner = s.session!;
        s.session = LocalSession(
          userId: owner.userId,
          name: owner.name,
          role: Role.cashier,
          storeId: s.storeId,
          deviceId: s.deviceId,
          expiresAt: owner.expiresAt,
        );
        await expectLater(
          s.createReturn(
            originalId: sale.id,
            items: [ReturnSelection(line, 1)],
            reason: 'Hủy sai đơn',
            received: 0,
            method: 'cash',
            voidOriginal: true,
          ),
          throwsStateError,
        );
        s.session = owner;
        await s.createReturn(
          originalId: sale.id,
          items: [ReturnSelection(line, 1)],
          reason: 'Hủy sai đơn',
          received: 0,
          method: 'cash',
          voidOriginal: true,
        );
        expect(
          (await s.db.rows('SELECT total FROM documents WHERE id=?', [
            sale.id,
          ])).single['total'],
          100000,
        );
        expect(
          (await s.db.rows(
            "SELECT * FROM document_events WHERE type='CANCELLED'",
          )).length,
          1,
        );
        expect(await s.returnableDocuments(), isEmpty);
      } finally {
        await s.db.close();
      }
    },
  );
}
