import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/backup/backup_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'Trước nâng cấp tạo snapshot có marker, đăng ký lịch sử/audit đúng một lần',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'nt-upgrade-backup-',
      );
      final path = '${folder.path}/live.sqlite';
      final first = AppDatabase(NativeDatabase(File(path)), filePath: path);
      final original = await salesFixture(database: first);
      final actor = original.session;
      await first.close();
      await backupBeforeUpgrade(path);
      final markers = await Directory('${folder.path}/upgrade-backups')
          .list()
          .toList();
      expect(markers.length, 1);
      final db = AppDatabase(NativeDatabase(File(path)), filePath: path);
      final s = LocalService(db, clock: () => DateTime.utc(2026, 11, 15))
        ..session = actor;
      try {
        final backup = BackupService(s);
        await backup.registerUpgradeBackups();
        await backup.registerUpgradeBackups();
        final records = await db.rows('SELECT * FROM backup_runs');
        expect(records.length, 1);
        await backup.verify(records.single['filename'] as String);
        expect(
          (await db.rows(
            "SELECT id FROM audit_logs WHERE action='BACKUP_UPGRADE_REGISTER'",
          )).length,
          1,
        );
        expect(
          await Directory('${folder.path}/upgrade-backups').list().toList(),
          isEmpty,
        );
      } finally {
        await db.close();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'Backup không truyền mật khẩu vẫn kế thừa cấu hình mã hóa đã lưu',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'backup_password': 'test-backup-encryption',
      });
      final folder = await Directory.systemTemp.createTemp(
        'nt-configured-backup-',
      );
      final s = await salesFixture();
      try {
        final backup = BackupService(s),
            path = await backup.create(folder: folder.path);
        expect(path, endsWith('.ntbackup'));
        await backup.verify(path, password: 'test-backup-encryption');
      } finally {
        await s.db.close();
        await folder.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'Snapshot khi DB đang mở, verify checksum/integrity và từ chối file hỏng',
    () async {
      final folder = await Directory.systemTemp.createTemp('nt-backup-test-');
      final service = await salesFixture();
      final backup = BackupService(service);
      try {
        final path = await backup.create(folder: folder.path);
        expect(await File(path).exists(), true);
        await backup.verify(path);
        expect(
          (await service.db.rows('SELECT quantity FROM stock_balances'))
              .single['quantity'],
          10,
        );
        await File(path).writeAsString('corrupted backup');
        await expectLater(backup.verify(path), throwsA(anything));
        expect(
          (await service.db.rows('SELECT quantity FROM stock_balances'))
              .single['quantity'],
          10,
        );
      } finally {
        await service.db.close();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'Khôi phục giữ pending outbox và khóa bán tới khi đối soát cloud',
    () async {
      final folder = await Directory.systemTemp.createTemp('nt-restore-test-');
      final source = File('${folder.path}/live.sqlite');
      final service = await salesFixture(
        database: AppDatabase(NativeDatabase(source), filePath: source.path),
      );
      final backup = BackupService(service);
      try {
        final snapshot = await backup.create(folder: folder.path);
        final sale = await service.sell(
          items: [const CartItem('v1', 1)],
          discount: 0,
          received: 100000,
          method: 'cash',
        );
        final before =
            (await service.db.rows('SELECT COUNT(*) AS n FROM outbox'))
                    .single['n']
                as int;
        await expectLater(
          backup.restore(
            snapshot,
            confirmation: 'WRONG',
            confirmed: true,
            reason: 'Kiểm thử xác nhận',
          ),
          throwsStateError,
        );
        await backup.restore(
          snapshot,
          confirmation: 'NT-CN01',
          confirmed: true,
          reason: 'Diễn tập khôi phục',
        );
        expect(service.restoreBlocked, true);
        expect(() => service.require(Permission.sell), throwsStateError);
        final restored = AppDatabase(NativeDatabase(source));
        try {
          expect(
            (await restored.rows(
              "SELECT value FROM local_settings WHERE key='restore_blocked'",
            )).single['value'],
            '1',
          );
          expect(
            (await restored.rows('SELECT COUNT(*) AS n FROM outbox'))
                    .single['n']
                as int,
            greaterThanOrEqualTo(before),
          );
          final pending = await restored.rows(
            "SELECT payload FROM outbox WHERE entity_type='sale'",
          );
          expect(pending.single['payload'].toString(), contains(sale.id));
          expect(await restored.rows('PRAGMA integrity_check'), isNotEmpty);
        } finally {
          await restored.close();
        }
      } finally {
        await service.db.close();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'Mã hóa backup: đúng mật khẩu mở được, sai mật khẩu không đổi dữ liệu',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'nt-encrypted-test-',
      );
      final service = await salesFixture();
      final backup = BackupService(service);
      try {
        final path = await backup.create(
          folder: folder.path,
          password: 'backup-test-password',
        );
        expect(path.endsWith('.ntbackup'), true);
        await backup.verify(path, password: 'backup-test-password');
        await expectLater(
          backup.verify(path, password: 'wrong-password'),
          throwsA(anything),
        );
      } finally {
        await service.db.close();
        await folder.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
