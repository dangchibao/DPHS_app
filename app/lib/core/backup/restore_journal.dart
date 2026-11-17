import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Future<void> recoverRestore(String databasePath) async {
  final source = File(databasePath),
      journal = File('$databasePath.restore-journal.json');
  if (!await journal.exists()) return;
  final data = Map<String, Object?>.from(
    jsonDecode(await journal.readAsString()) as Map,
  );
  final pending = File(data['pending'] as String),
      old = File(data['old'] as String),
      checksum = data['checksum'];
  final root = p.normalize(p.absolute(p.dirname(databasePath)));
  if (p.normalize(p.absolute(p.dirname(pending.path))) != root ||
      p.normalize(p.absolute(p.dirname(old.path))) != root ||
      pending.path != '$databasePath.restore-pending' ||
      !old.path.startsWith('$databasePath.before-restore-') ||
      checksum is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
    throw StateError('Nhật ký khôi phục không hợp lệ.');
  }
  if (await pending.exists()) {
    if ((await sha256.bind(pending.openRead()).first).toString() != checksum) {
      throw StateError(
        'Bản phục hồi chờ có checksum sai. Giữ nguyên dữ liệu để kiểm tra.',
      );
    }
    if (await source.exists() && !await old.exists()) {
      await source.rename(old.path);
    }
    if (!await source.exists()) await pending.rename(source.path);
  }
  if (!await source.exists() && await old.exists()) {
    await old.rename(source.path);
  }
  if (!await source.exists()) {
    throw StateError('Không tìm thấy database phục hồi hoặc bản hiện trạng.');
  }
  final db = sqlite.sqlite3.open(source.path, mode: sqlite.OpenMode.readOnly);
  try {
    if (db
        .select('PRAGMA integrity_check')
        .any((row) => row.values.single != 'ok')) {
      throw StateError('Database phục hồi không vượt integrity_check.');
    }
  } finally {
    db.close();
  }
  await journal.delete();
}
