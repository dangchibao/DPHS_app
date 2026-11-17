import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../auth/permissions.dart';
import '../app_version.dart';
import '../database/database.dart';
import '../local_service.dart';
import 'restore_journal.dart';

const currentAppVersion = appVersion;

// Kết nối file tạm riêng, không chia sẻ executor với database đang dùng.
class _RestoreDatabase extends AppDatabase {
  _RestoreDatabase(super.executor);
}

Future<void> backupBeforeUpgrade(String databasePath) async {
  final source = File(databasePath);
  if (!await source.exists()) return;
  final raw = sqlite.sqlite3.open(
    databasePath,
    mode: sqlite.OpenMode.readWrite,
  );
  Directory? temp;
  try {
    final version =
        raw.select('PRAGMA user_version').single.values.single as int;
    if (version > AppDatabase.currentSchemaVersion) {
      throw StateError(
        'Dữ liệu thuộc phiên bản mới hơn. Không hạ phiên bản ứng dụng.',
      );
    }
    if (version == 0) return;
    final hasSettings = raw
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='local_settings'",
        )
        .isNotEmpty;
    String? setting(String key) => !hasSettings
        ? null
        : raw.select('SELECT value FROM local_settings WHERE key=?', [
                key,
              ]).firstOrNull?['value']
              as String?;
    if (version == AppDatabase.currentSchemaVersion &&
        setting('last_app_version') == currentAppVersion) {
      return;
    }
    final identityStore =
            setting('identity_store') ??
            (raw.select('SELECT id FROM stores WHERE id=?', [
                  LocalService.defaultStoreId,
                ]).isNotEmpty
                ? LocalService.defaultStoreId
                : null),
        identityDevice =
            setting('identity_device') ??
            (raw.select('SELECT id FROM devices WHERE id=?', [
                  LocalService.defaultDeviceId,
                ]).isNotEmpty
                ? LocalService.defaultDeviceId
                : null);
    final stores = identityStore == null
        ? raw.select('SELECT id,code FROM stores LIMIT 1')
        : raw.select('SELECT id,code FROM stores WHERE id=?', [identityStore]);
    if (stores.isEmpty) {
      if (identityStore != null) {
        throw StateError(
          'Danh tính cửa hàng không tồn tại. Không tự nâng cấp.',
        );
      }
      return;
    }
    final store = stores.single,
        devices = identityDevice == null
            ? raw.select(
                'SELECT id,code FROM devices WHERE store_id=? LIMIT 1',
                [store['id']],
              )
            : raw.select(
                'SELECT id,code FROM devices WHERE store_id=? AND id=?',
                [store['id'], identityDevice],
              );
    if (devices.isEmpty) {
      throw StateError('Dữ liệu thiếu thiết bị. Không tự nâng cấp.');
    }
    final device = devices.single;
    final folder = Directory(
      setting('backup_folder') ?? p.join(source.parent.path, 'backups'),
    );
    await folder.create(recursive: true);
    temp = await Directory.systemTemp.createTemp('nt-preupgrade-');
    final snapshot = p.join(temp.path, 'database.sqlite');
    raw.execute('PRAGMA busy_timeout=5000');
    raw.execute('VACUUM INTO ?', [snapshot]);
    final password = await const FlutterSecureStorage().read(
      key: 'backup_password',
    );
    final encrypted = password != null && password.isNotEmpty;
    final target = p.join(
      folder.path,
      '${store['code']}-${device['code']}-before-upgrade-${DateTime.now().toUtc().millisecondsSinceEpoch}.${encrypted ? 'ntbackup' : 'zip'}',
    );
    final created = DateTime.now().toUtc().toIso8601String();
    final result = await compute(_pack, {
      'snapshot': snapshot,
      'zip': p.join(temp.path, 'backup.zip'),
      'target': target,
      'password': password,
      'store_id': store['id'],
      'device_id': device['id'],
      'created_at': created,
      'schema_version': version,
      'installation_hash': setting('installation_hash') ?? '',
    });
    final markerId = const Uuid().v7();
    final markers = Directory(p.join(source.parent.path, 'upgrade-backups'));
    await markers.create(recursive: true);
    await File(p.join(markers.path, '$markerId.json')).writeAsString(
      jsonEncode({
        'id': markerId,
        'path': target,
        'store_id': store['id'],
        'device_id': device['id'],
        'created_at': created,
        'encrypted': encrypted,
        'checksum': result['checksum'],
        'bytes': result['bytes'],
        'from_schema': version,
      }),
      flush: true,
    );
  } finally {
    raw.close();
    if (temp != null) await temp.delete(recursive: true);
  }
}

Future<String> fileChecksum(File file) async =>
    (await hash.sha256.bind(file.openRead()).first).toString();
void checkDatabase(String path) {
  final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
  try {
    if (db
        .select('PRAGMA integrity_check')
        .any((row) => row.values.single != 'ok')) {
      throw StateError('Bản sao lưu không vượt qua integrity_check.');
    }
  } finally {
    db.close();
  }
}

Future<SecretKey> _backupKey(String password, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: 600000,
  bits: 256,
).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
List<int> _random(int n) {
  final random = Random.secure();
  return List.generate(n, (_) => random.nextInt(256));
}

Future<void> encryptBackup(
  String source,
  String target,
  String password,
) async {
  if (password.length < 10) {
    throw ArgumentError('Mật khẩu backup tối thiểu 10 ký tự.');
  }
  final salt = _random(16), nonce = _random(12), cipher = AesGcm.with256bits();
  final header = utf8.encode(
    'NTBACKUP1\n${jsonEncode({'kdf': 'PBKDF2-SHA256', 'iterations': 600000, 'salt': base64Encode(salt), 'nonce': base64Encode(nonce)})}\n',
  );
  final output = File(target).openWrite();
  output.add(header);
  Mac? mac;
  try {
    await output.addStream(
      cipher.encryptStream(
        File(source).openRead(),
        secretKey: await _backupKey(password, salt),
        nonce: nonce,
        aad: header,
        onMac: (value) => mac = value,
      ),
    );
    output.add(mac!.bytes);
    await output.flush();
  } finally {
    await output.close();
  }
}

Future<void> decryptBackup(
  String source,
  String target,
  String password,
) async {
  final file = File(source), input = await file.open();
  late List<int> headerBytes, mac;
  late Map<String, Object?> header;
  late int offset, length;
  try {
    length = await input.length();
    final prefix = await input.read(min(length, 2048));
    final first = prefix.indexOf(10), second = prefix.indexOf(10, first + 1);
    if (first < 0 ||
        second < 0 ||
        ascii.decode(prefix.sublist(0, first)) != 'NTBACKUP1') {
      throw StateError('Định dạng backup không hợp lệ.');
    }
    headerBytes = prefix.sublist(0, second + 1);
    header = Map<String, Object?>.from(
      jsonDecode(utf8.decode(prefix.sublist(first + 1, second))) as Map,
    );
    if (header['iterations'] != 600000 || header['kdf'] != 'PBKDF2-SHA256') {
      throw StateError('Không hỗ trợ định dạng mã hóa.');
    }
    offset = second + 1;
    if (length < offset + 16) throw StateError('Backup bị cắt ngắn.');
    await input.setPosition(length - 16);
    mac = await input.read(16);
  } finally {
    await input.close();
  }
  final output = File(target).openWrite();
  try {
    await output.addStream(
      AesGcm.with256bits().decryptStream(
        file.openRead(offset, length - 16),
        secretKey: await _backupKey(
          password,
          base64Decode(header['salt'] as String),
        ),
        nonce: base64Decode(header['nonce'] as String),
        mac: Mac(mac),
        aad: headerBytes,
      ),
    );
    await output.flush();
  } finally {
    await output.close();
  }
}

Future<Map<String, Object?>> _pack(Map<String, Object?> args) async {
  final snapshot = File(args['snapshot'] as String),
      zip = args['zip'] as String,
      target = args['target'] as String;
  checkDatabase(snapshot.path);
  final checksum = await fileChecksum(snapshot);
  final manifest = {
    'format': 1,
    'store_id': args['store_id'],
    'device_id': args['device_id'],
    'created_at': args['created_at'],
    'schema_version': args['schema_version'],
    'sha256': checksum,
    'installation_hash': args['installation_hash'],
  };
  final manifestFile = File(p.join(snapshot.parent.path, 'manifest.json'));
  await manifestFile.writeAsString(jsonEncode(manifest));
  final encoder = ZipFileEncoder()..create(zip);
  try {
    await encoder.addFile(snapshot, 'database.sqlite');
    await encoder.addFile(manifestFile, 'manifest.json');
  } finally {
    encoder.close();
  }
  final password = args['password'] as String?;
  if (password == null || password.isEmpty) {
    await File(zip).rename(target);
  } else {
    await encryptBackup(zip, target, password);
  }
  return {
    'checksum': await fileChecksum(File(target)),
    'bytes': await File(target).length(),
  };
}

Future<Map<String, Object?>> _unpack(Map<String, Object?> args) async {
  final source = args['source'] as String,
      directory = args['directory'] as String;
  var zip = source;
  if (source.endsWith('.ntbackup')) {
    zip = p.join(directory, 'decrypted.zip');
    await decryptBackup(source, zip, args['password'] as String? ?? '');
  }
  final input = InputFileStream(zip);
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    if (archive.files.length != 2 ||
        archive.files.any(
          (f) =>
              !['database.sqlite', 'manifest.json'].contains(f.name) ||
              !f.isFile ||
              f.size > 4 * 1024 * 1024 * 1024,
        )) {
      throw StateError('Nội dung backup không hợp lệ.');
    }
    for (final entry in archive.files) {
      final output = OutputFileStream(p.join(directory, entry.name));
      try {
        entry.writeContent(output);
      } finally {
        await output.close();
      }
    }
  } finally {
    await input.close();
  }
  final manifest = Map<String, Object?>.from(
    jsonDecode(await File(p.join(directory, 'manifest.json')).readAsString())
        as Map,
  );
  final snapshot = File(p.join(directory, 'database.sqlite'));
  if (manifest['format'] != 1 ||
      manifest['sha256'] != await fileChecksum(snapshot)) {
    throw StateError('Checksum bản sao lưu không khớp.');
  }
  checkDatabase(snapshot.path);
  return manifest;
}

class BackupService {
  BackupService(this.service);
  final LocalService service;
  bool _busy = false;
  Future<void> registerUpgradeBackups() async {
    if (service.db.filePath == null || service.session == null) return;
    final directory = Directory(
      p.join(p.dirname(service.db.filePath!), 'upgrade-backups'),
    );
    if (!await directory.exists()) return;
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final marker = Map<String, Object?>.from(
        jsonDecode(await entry.readAsString()) as Map,
      );
      if (marker['store_id'] != service.storeId ||
          marker['device_id'] != service.deviceId) {
        throw StateError('Marker backup khác danh tính thiết bị.');
      }
      final previous = await service.db.rows(
        'SELECT id FROM backup_runs WHERE store_id=? AND id=?',
        [service.storeId, marker['id']],
      );
      if (previous.isEmpty) {
        final file = File(marker['path'] as String);
        if (!await file.exists() ||
            await file.length() != marker['bytes'] ||
            await fileChecksum(file) != marker['checksum']) {
          throw StateError(
            'Bản sao lưu trước nâng cấp bị thiếu hoặc sai checksum.',
          );
        }
        await service.db.transaction(() async {
          await service.db.execute(
            'INSERT INTO backup_runs VALUES (?,?,?,?,?,?,?,?,?,?,?)',
            [
              marker['id'],
              service.storeId,
              service.deviceId,
              file.path,
              marker['bytes'],
              marker['checksum'],
              marker['created_at'],
              service.now,
              marker['encrypted'] == true ? 1 : 0,
              'success',
              '',
            ],
          );
          await service.audit(
            'BACKUP_UPGRADE_REGISTER',
            'backup',
            p.basename(file.path),
            reason: 'Ghi nhận bản sao lưu tự động trước nâng cấp',
            changes: {
              'from_schema': marker['from_schema'],
              'encrypted': marker['encrypted'],
              'created_at': marker['created_at'],
            },
          );
        });
      }
      await entry.delete();
    }
  }

  Future<void> rotate(
    String folder, {
    int days = 7,
    int weeks = 4,
    int months = 12,
  }) {
    service.require(Permission.backup);
    return _rotate(folder, days: days, weeks: weeks, months: months);
  }

  Future<void> _rotate(
    String folder, {
    int days = 7,
    int weeks = 4,
    int months = 12,
  }) async {
    if (days < 1 || weeks < 1 || months < 1) {
      throw ArgumentError('Số bản giữ lại phải lớn hơn 0.');
    }
    final root = await Directory(folder).resolveSymbolicLinks();
    final rows = await service.db.rows(
      "SELECT * FROM backup_runs WHERE store_id=? AND device_id=? AND status='success' ORDER BY created_at DESC",
      [service.storeId, service.deviceId],
    );
    final keep = <String>{},
        dayKeys = <String>{},
        weekKeys = <String>{},
        monthKeys = <String>{};
    for (final row in rows) {
      final time = DateTime.parse(row['created_at'] as String)
          .toUtc()
          .add(const Duration(hours: 7));
      final day = DateFormat('yyyy-MM-dd').format(time),
          week = DateFormat('yyyy-MM-dd')
              .format(time.subtract(Duration(days: time.weekday - 1))),
          month = DateFormat('yyyy-MM').format(time);
      var retain = false;
      if (!dayKeys.contains(day) && dayKeys.length < days) {
        dayKeys.add(day);
        retain = true;
      }
      if (!weekKeys.contains(week) && weekKeys.length < weeks) {
        weekKeys.add(week);
        retain = true;
      }
      if (!monthKeys.contains(month) && monthKeys.length < months) {
        monthKeys.add(month);
        retain = true;
      }
      if (retain) keep.add(row['id'] as String);
    }
    var count = 0;
    for (final row in rows.where((row) => !keep.contains(row['id']))) {
      final file = File(row['filename'] as String);
      if (!await file.exists()) continue;
      final resolved = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved) || p.dirname(resolved) != root) continue;
      if (!RegExp(
        r'^NT-CN[A-Z0-9]+-[A-Z0-9]+-\d{8}-\d{6}-[a-f0-9]+\.(zip|ntbackup)$',
      ).hasMatch(p.basename(resolved))) {
        continue;
      }
      await file.delete();
      count++;
      await service.db.execute(
        "UPDATE backup_runs SET status='rotated' WHERE id=?",
        [row['id']],
      );
    }
    if (count > 0) {
      await service.db.transaction(
        () => service.audit(
          'BACKUP_ROTATE',
          'backup',
          'retention',
          reason: 'Xoay vòng bản đã kiểm chứng',
          changes: {'removed': count},
        ),
      );
    }
  }

  Future<String> create({
    String? folder,
    String? password,
    String reason = 'Sao lưu thủ công',
  }) {
    service.require(Permission.backup);
    if (service.maintenance) throw StateError('Đang khôi phục dữ liệu.');
    return _create(folder: folder, password: password, reason: reason);
  }

  Future<String> _create({
    String? folder,
    String? password,
    required String reason,
  }) async {
    await registerUpgradeBackups();
    password ??= await const FlutterSecureStorage().read(
      key: 'backup_password',
    );
    if (_busy) throw StateError('Đang có tác vụ sao lưu.');
    _busy = true;
    final temp = await Directory.systemTemp.createTemp('nt-backup-');
    String? target;
    var verified = false;
    try {
      final root = Directory(
        folder ??
            p.join(
              service.db.filePath == null
                  ? (await getApplicationSupportDirectory()).path
                  : p.dirname(service.db.filePath!),
              'backups',
            ),
      );
      await root.create(recursive: true);
      final store = (await service.db.rows(
        'SELECT code FROM stores WHERE id=?',
        [service.storeId],
      )).single['code'];
      final device = (await service.db.rows(
        'SELECT code FROM devices WHERE id=?',
        [service.deviceId],
      )).single['code'];
      final time = DateFormat('yyyyMMdd-HHmmss')
          .format(service.clock().toUtc().add(const Duration(hours: 7)));
      final encrypted = password != null && password.isNotEmpty;
      target = p.join(
        root.path,
        '$store-$device-$time-${service.uuid.v7().substring(28)}.${encrypted ? 'ntbackup' : 'zip'}',
      );
      final snapshot = p.join(temp.path, 'database.sqlite');
      await service.db.execute('VACUUM INTO ?', [snapshot]);
      final result = await compute(_pack, {
        'snapshot': snapshot,
        'zip': p.join(temp.path, 'backup.zip'),
        'target': target,
        'password': password,
        'store_id': service.storeId,
        'device_id': service.deviceId,
        'created_at': service.now,
        'schema_version': service.db.schemaVersion,
        'installation_hash': service.installationHash,
      });
      verified = true;
      await service.db.transaction(() async {
        await service.db.execute(
          'INSERT INTO backup_runs VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          [
            service.uuid.v7(),
            service.storeId,
            service.deviceId,
            target,
            result['bytes'],
            result['checksum'],
            service.now,
            service.now,
            encrypted ? 1 : 0,
            'success',
            '',
          ],
        );
        await service.audit(
          'BACKUP_SUCCESS',
          'backup',
          p.basename(target!),
          reason: reason,
          changes: {'encrypted': encrypted, 'bytes': result['bytes']},
        );
      });
      return target;
    } catch (e) {
      if (!verified && target != null && await File(target).exists()) {
        await File(target).delete();
      }
      rethrow;
    } finally {
      _busy = false;
      await temp.delete(recursive: true);
    }
  }

  Future<void> verify(String path, {String? password}) async {
    service.require(Permission.backup);
    await _verify(path, password: password);
  }

  Future<void> _verify(String path, {String? password}) async {
    final temp = await Directory.systemTemp.createTemp('nt-verify-');
    try {
      await compute(_unpack, {
        'source': path,
        'directory': temp.path,
        'password': password,
      });
      await service.db.transaction(
        () => service.audit(
          'BACKUP_VERIFY',
          'backup',
          p.basename(path),
          reason: 'Khôi phục thử vào file tạm',
        ),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<void> restore(
    String path, {
    String? password,
    required String confirmation,
    required bool confirmed,
    required String reason,
  }) async {
    service.require(Permission.backup);
    if (reason.trim().isEmpty) {
      throw StateError('Nhập lý do khôi phục dữ liệu.');
    }
    final store = (await service.db.rows('SELECT code FROM stores WHERE id=?', [
      service.storeId,
    ])).single['code'];
    if (!confirmed || confirmation != store) {
      throw StateError('Cần xác nhận hai bước và nhập đúng mã cửa hàng.');
    }
    final temp = await Directory.systemTemp.createTemp('nt-restore-');
    try {
      final manifest = await compute(_unpack, {
        'source': path,
        'directory': temp.path,
        'password': password,
      });
      if (manifest['store_id'] != service.storeId ||
          manifest['device_id'] != service.deviceId ||
          manifest['installation_hash'] != service.installationHash) {
        throw StateError(
          'Bản sao lưu khác cửa hàng, thiết bị hoặc máy cài đặt. Cần quy trình đăng ký thiết bị mới.',
        );
      }
      service.maintenance = true;
      await service.syncEngine?.pauseAndDrain();
      await _create(reason: 'Sao lưu hiện trạng trước khôi phục');
      final sourcePath = service.db.filePath;
      if (sourcePath == null) {
        throw StateError('Database không có đường dẫn khôi phục.');
      }
      // Migrate bản phục hồi tạm, giữ nguyên database đang dùng tới khi đã kiểm chứng.
      final restored = _RestoreDatabase(
        NativeDatabase(File(p.join(temp.path, 'database.sqlite'))),
      );
      try {
        await restored.rows('SELECT 1');
        await restored.execute('ATTACH DATABASE ? AS current_live', [
          sourcePath,
        ]);
        await restored.transaction(() async {
          // Chỉ ghép outbox và audit, không làm mất các giao dịch chưa gửi của hiện trạng.
          final conflicts = await restored.rows(
            'SELECT a.id FROM main.audit_logs a JOIN current_live.audit_logs b ON a.store_id=b.store_id AND a.device_id=b.device_id AND a.chain_index=b.chain_index WHERE a.hash<>b.hash LIMIT 1',
          );
          if (conflicts.isNotEmpty) {
            throw StateError(
              'Phát hiện nhánh nhật ký khác nhau. Không tự khôi phục đè.',
            );
          }
          final queueConflicts = await restored.rows(
            'SELECT a.id FROM main.outbox a JOIN current_live.outbox b ON a.id=b.id WHERE a.store_id<>b.store_id OR a.device_id<>b.device_id OR a.payload<>b.payload OR a.entity_type<>b.entity_type OR COALESCE(a.actor_id,\'\')<>COALESCE(b.actor_id,\'\') LIMIT 1',
          );
          if (queueConflicts.isNotEmpty) {
            throw StateError(
              'Hàng đợi có cùng mã nhưng nội dung khác. Không tự khôi phục đè.',
            );
          }
          await restored.execute(
            'INSERT OR IGNORE INTO main.audit_logs SELECT * FROM current_live.audit_logs',
          );
          await restored.execute(
            'INSERT OR IGNORE INTO main.local_audit_receipts SELECT * FROM current_live.local_audit_receipts',
          );
          await restored.execute(
            'INSERT OR IGNORE INTO main.outbox SELECT * FROM current_live.outbox',
          );
          await restored.execute(
            'INSERT OR IGNORE INTO main.backup_runs SELECT * FROM current_live.backup_runs',
          );
          await restored.execute(
            "INSERT INTO local_settings VALUES ('restore_blocked','1') ON CONFLICT(key) DO UPDATE SET value='1'",
          );
          await restored.execute(
            "INSERT INTO local_settings VALUES ('restore_reason','restore') ON CONFLICT(key) DO UPDATE SET value='restore'",
          );
          await restored.execute('DELETE FROM sync_cursors');
          final restoredService = LocalService(
            restored,
            storeId: service.storeId,
            deviceId: service.deviceId,
            clock: service.clock,
          )..session = service.session;
          await restoredService.audit(
            'RESTORE_APPLY',
            'backup',
            p.basename(path),
            reason: reason.trim(),
            severity: 'critical',
          );
        });
        await restored.execute('DETACH DATABASE current_live');
      } finally {
        await restored.close();
      }
      checkDatabase(p.join(temp.path, 'database.sqlite'));
      await service.db.close(releaseLock: false);
      // Nhật ký cho phép tiếp tục/rollback khi mất điện giữa hai lần rename.
      final pending = File('$sourcePath.restore-pending');
      await File(p.join(temp.path, 'database.sqlite')).copy(pending.path);
      final old = File('$sourcePath.before-restore-${service.uuid.v7()}');
      await File('$sourcePath.restore-journal.json').writeAsString(
        jsonEncode({
          'pending': pending.path,
          'old': old.path,
          'checksum': await fileChecksum(pending),
        }),
        flush: true,
      );
      await recoverRestore(sourcePath);
      service.restoreBlocked = true;
      service.session = null;
    } finally {
      service.maintenance = false;
      if (service.db.isClosed) await service.db.releaseFileLock();
      await temp.delete(recursive: true);
    }
  }
}

class BackupScheduler extends WidgetsBindingObserver {
  BackupScheduler(this.service, this.backup);
  final LocalService service;
  final BackupService backup;
  Timer? _timer;
  bool _working = false;
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => tick());
  }

  Future<void> tick({bool exiting = false}) async {
    if (_working || service.maintenance || service.db.isClosed) return;
    _working = true;
    try {
      if (!await service.initialized) return;
      if (service.session == null &&
          (await service.db.rows(
            "SELECT value FROM local_settings WHERE key='last_authenticated_user'",
          )).isEmpty) {
        return;
      }
      await backup.registerUpgradeBackups();
      final settings = await service.db.rows(
        "SELECT key,value FROM local_settings WHERE key IN ('backup_folder','backup_hour','backup_minute','backup_days','backup_weeks','backup_months')",
      );
      final config = {
        for (final row in settings)
          row['key'] as String: row['value'] as String,
      };
      final latest = await service.db.rows(
        "SELECT * FROM backup_runs WHERE store_id=? AND device_id=? AND status='success' ORDER BY created_at DESC LIMIT 1",
        [service.storeId, service.deviceId],
      );
      final now = service.clock().toUtc().add(const Duration(hours: 7)),
          today = DateFormat('yyyyMMdd').format(now);
      final hour = int.tryParse(config['backup_hour'] ?? '') ?? 21,
          minute = int.tryParse(config['backup_minute'] ?? '') ?? 30;
      final last = latest.isEmpty
          ? null
          : DateTime.parse(latest.single['created_at'] as String);
      final alreadyToday =
          last != null &&
          DateFormat('yyyyMMdd')
                  .format(last.toUtc().add(const Duration(hours: 7))) ==
              today;
      final due = now.hour * 60 + now.minute >= hour * 60 + minute;
      final stale =
          last == null ||
          service.clock().difference(last) > const Duration(days: 2);
      if (exiting || !alreadyToday && (due || stale)) {
        final password = await const FlutterSecureStorage().read(
          key: 'backup_password',
        );
        final path = await backup._create(
          folder: config['backup_folder'],
          password: password,
          reason: exiting
              ? 'Tự động khi thoát app'
              : 'Tự động theo lịch / bù lịch',
        );
        final folder = p.dirname(path);
        await backup._rotate(
          folder,
          days: int.tryParse(config['backup_days'] ?? '') ?? 7,
          weeks: int.tryParse(config['backup_weeks'] ?? '') ?? 4,
          months: int.tryParse(config['backup_months'] ?? '') ?? 12,
        );
        final checks = await service.db.rows(
          "SELECT value FROM local_settings WHERE key='last_restore_drill'",
        );
        if (checks.isEmpty ||
            service.clock().difference(
                  DateTime.parse(checks.single['value'] as String),
                ) >=
                const Duration(days: 7)) {
          await backup._verify(path, password: password);
          await service.db.execute(
            "INSERT INTO local_settings VALUES ('last_restore_drill',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [service.now],
          );
        }
        await service.db.execute(
          "DELETE FROM local_settings WHERE key='backup_error'",
        );
      }
    } catch (error) {
      if (!service.db.isClosed) {
        await service.db.execute(
          "INSERT INTO local_settings VALUES ('backup_error',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
          [error.toString()],
        );
      }
    } finally {
      _working = false;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await tick(exiting: true);
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) tick();
    if (state == AppLifecycleState.detached) tick(exiting: true);
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
