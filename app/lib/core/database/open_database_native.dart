import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import '../backup/restore_journal.dart';
import '../backup/backup_native.dart' show backupBeforeUpgrade;

Future<AppDatabase> openAppDatabase() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, 'ngoc_thanh.sqlite'));
  final lock = await File('${file.path}.lock').open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
  } catch (_) {
    await lock.close();
    throw StateError(
      'Ứng dụng đang mở ở cửa sổ khác. Chỉ mở một phiên trên mỗi thiết bị.',
    );
  }
  try {
    await recoverRestore(file.path);
    await backupBeforeUpgrade(file.path);
    return AppDatabase(
      NativeDatabase.createInBackground(file),
      filePath: file.path,
      onClosed: () async {
        await lock.unlock();
        await lock.close();
      },
    );
  } catch (_) {
    await lock.unlock();
    await lock.close();
    rethrow;
  }
}
