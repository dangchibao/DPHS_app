import 'package:file_picker/file_picker.dart';

Future<T> withBackupFile<T>(
  PlatformFile file,
  Future<T> Function(String path) action,
) => throw UnsupportedError('Khôi phục cục bộ chỉ hỗ trợ Windows/Android.');
