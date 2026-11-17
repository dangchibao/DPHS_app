import '../local_service.dart';

Future<void> backupBeforeUpgrade(String databasePath) => throw UnsupportedError(
  'Sao lưu trước nâng cấp chỉ hỗ trợ Windows/Android.',
);

class BackupService {
  BackupService(LocalService service);
  Future<void> registerUpgradeBackups() async {}
  Future<void> rotate(
    String folder, {
    int days = 7,
    int weeks = 4,
    int months = 12,
  }) => throw UnsupportedError(
    'Xoay vòng backup cục bộ chỉ hỗ trợ Windows/Android.',
  );
  Future<String> create({
    String? folder,
    String? password,
    String reason = 'Sao lưu thủ công',
  }) => throw UnsupportedError('Sao lưu SQLite chỉ hỗ trợ Windows/Android.');
  Future<void> verify(String path, {String? password}) =>
      throw UnsupportedError(
        'Kiểm tra backup SQLite chỉ hỗ trợ Windows/Android.',
      );
  Future<void> restore(
    String path, {
    String? password,
    required String confirmation,
    required bool confirmed,
    required String reason,
  }) => throw UnsupportedError('Khôi phục SQLite chỉ hỗ trợ Windows/Android.');
}

class BackupScheduler {
  BackupScheduler(LocalService service, BackupService backup);
  void start() {}
  void dispose() {}
}
