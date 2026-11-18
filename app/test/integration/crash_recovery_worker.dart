import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import '../fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['NT_CRASH_DB'],
      phase = Platform.environment['NT_CRASH_PHASE'];
  test('Giao dịch POS khi tiến trình bị ngắt: $phase', () async {
    if (path == null || phase == null) {
      throw StateError(
        'Chỉ chạy bằng scripts/crash_recovery_test.py với database tạm.',
      );
    }
    final file = File(path), db = AppDatabase(NativeDatabase(file));
    final s = phase == 'before'
        ? await salesFixture(database: db)
        : LocalService(db, clock: () => DateTime.utc(2026, 11, 15));
    addTearDown(db.close);
    s.session = LocalSession(
      userId: 'u1',
      name: 'Chủ',
      role: Role.owner,
      storeId: s.storeId,
      deviceId: s.deviceId,
      expiresAt: DateTime.utc(2027),
    );
    await db.execute('PRAGMA journal_mode=WAL');
    await db.execute('PRAGMA synchronous=FULL');
    Future<SaleResult> sale(String command) => s.sell(
      items: [const CartItem('v1', 1)],
      discount: 0,
      received: 100000,
      method: 'cash',
      commandId: command,
    );
    Future<void> ready() async {
      await File('$path.ready').writeAsString(phase, flush: true);
      await Completer<void>().future;
    }

    if (phase == 'before') {
      await db.transaction(() async {
        final result = await sale('crash-command');
        expect(result.code.endsWith('-001'), true);
        await ready();
      });
    } else if (phase == 'after') {
      expect(await db.rows('SELECT id FROM documents'), isEmpty);
      expect(await db.rows('SELECT * FROM document_counters'), isEmpty);
      expect(
        (await db.rows('SELECT quantity FROM stock_balances'))
            .single['quantity'],
        10,
      );
      final result = await sale('crash-command');
      expect(result.code.endsWith('-001'), true);
      await ready();
    } else if (phase == 'recover') {
      expect(
        (await db.rows('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rows('PRAGMA foreign_key_check'), isEmpty);
      expect((await db.rows('SELECT id FROM documents')).length, 1);
      final replay = await sale('crash-command');
      expect(replay.code, 'HD-CN01-A2-20261115-001');
      expect(
        (await db.rows('SELECT quantity FROM stock_balances'))
            .single['quantity'],
        9,
      );
      expect(
        (await db.rows("SELECT id FROM outbox WHERE entity_type='sale'"))
            .length,
        1,
      );
      final next = await sale('next-command');
      expect(next.code, 'HD-CN01-A2-20261115-002');
      expect(
        (await db.rows('SELECT quantity FROM stock_balances'))
            .single['quantity'],
        8,
      );
      expect(
        (await db.rows('SELECT COUNT(*) n FROM documents')).single['n'],
        2,
      );
    } else {
      throw StateError('Phase không hợp lệ.');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
