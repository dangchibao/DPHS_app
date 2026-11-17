import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

Future<T> withBackupFile<T>(
  PlatformFile file,
  Future<T> Function(String path) action,
) async {
  if (!['zip', 'ntbackup'].contains(file.extension)) {
    throw ArgumentError('Chọn tệp backup .zip hoặc .ntbackup.');
  }
  if (file.path != null) return action(file.path!);
  final temp = await Directory.systemTemp.createTemp('nt-picked-backup-');
  try {
    final target = File(p.join(temp.path, p.basename(file.name))),
        sinkPath = p.basename(file.name);
    if (sinkPath == '.' || sinkPath == '..' || sinkPath.isEmpty) {
      throw ArgumentError('Tên tệp không hợp lệ.');
    }
    final output = target.openWrite();
    try {
      await output.addStream(file.readAsByteStream());
      await output.flush();
    } finally {
      await output.close();
    }
    return await action(target.path);
  } finally {
    await temp.delete(recursive: true);
  }
}
