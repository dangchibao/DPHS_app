import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/auth/password.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Login biết fence thì thu hồi lease offline ngay, giữ queue và cần xác thực online để mở lại', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    await s.db.execute(
      "INSERT INTO employee_store_assignments VALUES('fixture-owner','store-cn01','u1','owner',1,'2026-11-15')",
    );
    final salt = Passwords.salt();
    await s.db.execute('UPDATE users SET password_hash=?,salt=? WHERE id=?', [
      await Passwords.hash('fixture-password', salt),
      salt,
      'u1',
    ]);
    await s.db.execute('INSERT INTO local_settings VALUES(?,?)', [
      'grant:u1',
      DateTime.utc(2027).toIso8601String(),
    ]);
    final before = (await s.db.rows('SELECT id FROM outbox')).length;
    s.onlineLogin = (_, _) async =>
        throw const CloudError(403, 'STAFF_HANDOFF_PENDING', 'Đang bàn giao');
    await expectLater(
      s.login('admin', 'fixture-password'),
      throwsA(isA<CloudError>()),
    );
    expect(
      await s.db.rows("SELECT value FROM local_settings WHERE key='grant:u1'"),
      isEmpty,
    );
    expect(s.session!.expiresAt.isAfter(s.clock()), false);
    expect((await s.db.rows('SELECT id FROM outbox')).length, before);
    s.onlineLogin = null;
    await expectLater(s.login('admin', 'fixture-password'), throwsStateError);
    expect((await s.db.rows('SELECT id FROM outbox')).length, before);
    s.onlineLogin = (_, _) async => {
      'user': {
        'id': 'u1',
        'name': 'Chủ',
        'role': 'owner',
        'must_change_password': false,
      },
      'expires_at': DateTime.utc(2027).toIso8601String(),
    };
    final restored = await s.login('admin', 'fixture-password');
    expect(restored.expiresAt.isAfter(s.clock()), true);
  });
}
