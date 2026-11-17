import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Sai mật khẩu không xóa lease, cloud thu hồi đúng tài khoản thì chặn đăng nhập offline', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final service = LocalService(db, clock: () => DateTime.utc(2026, 11, 15));
    try {
      await service.bootstrap('password-for-tests-only');
      service.onlineLogin = (_, _) async =>
          throw const CloudError(401, 'UNAUTHORIZED', 'Không thể đăng nhập');
      await expectLater(
        service.login('admin', 'wrong'),
        throwsA(isA<CloudError>()),
      );
      expect(
        await db.rows(
          "SELECT value FROM local_settings WHERE key='grant:admin'",
        ),
        hasLength(1),
      );
      await expectLater(
        service.login('admin', 'password-for-tests-only'),
        throwsA(isA<CloudError>()),
      );
      expect(
        await db.rows(
          "SELECT value FROM local_settings WHERE key='grant:admin'",
        ),
        isEmpty,
      );
      service.onlineLogin = null;
      await expectLater(
        service.login('admin', 'password-for-tests-only'),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
  });
  test(
    'Cloud phát hiện bản sao thiết bị lưu khóa nghiệp vụ bền vững',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final service = LocalService(db);
      try {
        service.onlineLogin = (_, _) async =>
            throw const CloudError(403, 'DEVICE_IDENTITY', 'Sai thiết bị');
        await expectLater(
          service.login('admin', 'test'),
          throwsA(isA<CloudError>()),
        );
        expect(service.restoreBlocked, true);
        expect(
          (await db.rows(
            "SELECT value FROM local_settings WHERE key='restore_reason'",
          )).single['value'],
          'identity',
        );
      } finally {
        await db.close();
      }
    },
  );
}
