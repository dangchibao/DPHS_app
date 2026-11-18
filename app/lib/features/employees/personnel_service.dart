import '../../core/local_service.dart';
import '../../core/auth/password.dart';
import '../../core/auth/permissions.dart';

extension PersonnelService on LocalService {
  Future<List<Map<String, Object?>>> employees() {
    require(Permission.staff);
    return db.rows(
      '''SELECT u.id,u.username,u.display_name,(u.active AND a.active) AS active,a.role,a.store_id FROM users u
     JOIN employee_store_assignments a ON a.user_id=u.id WHERE a.store_id=? ORDER BY u.display_name''',
      [storeId],
    );
  }

  Future<void> saveEmployee({
    String? id,
    required String username,
    required String name,
    required Role role,
    String? password,
    required String reason,
    bool active = true,
  }) async {
    final actor = require(Permission.staff);
    if (name.trim().isEmpty ||
        username.trim().isEmpty ||
        reason.trim().isEmpty) {
      throw ArgumentError('Nhập tài khoản, họ tên và lý do.');
    }
    if (id == actor.userId) {
      throw StateError(
        'Không tự thay đổi quyền hoặc khóa tài khoản đang dùng.',
      );
    }
    final existing = id == null
        ? <Map<String, Object?>>[]
        : await db.rows(
            'SELECT role FROM employee_store_assignments WHERE store_id=? AND user_id=?',
            [storeId, id],
          );
    if (actor.role != Role.owner &&
        (role == Role.owner ||
            role == Role.manager ||
            existing.any((e) => ['owner', 'manager'].contains(e['role'])))) {
      throw StateError('Chỉ chủ được thay đổi quyền quản lý.');
    }
    String? salt, hash;
    if (id == null) {
      if (password == null || password.length < 10) {
        throw ArgumentError('Mật khẩu tối thiểu 10 ký tự.');
      }
      salt = Passwords.salt();
      hash = await Passwords.hash(password, salt);
    }
    final target = id ?? uuid.v7();
    if (onlineStaff != null) {
      final response = await onlineStaff!({
        'id': target,
        'username': username,
        'display_name': name,
        'role': role.name,
        'active': active,
        'reason': reason,
        if (id == null) 'password': password,
      });
      if (response['handoff_required'] == true) {
        throw StateError(
          'Đã tạo yêu cầu bàn giao. Mở “Bàn giao quyền” để chờ các máy gửi hết hàng đợi rồi hoàn tất.',
        );
      }
    }
    await db.transaction(() async {
      if (id == null) {
        await db.execute('INSERT INTO users VALUES (?,?,?,?,?,?,?,?)', [
          target,
          username.trim(),
          name.trim(),
          hash,
          salt,
          active ? 1 : 0,
          1,
          now,
        ]);
        await db.execute(
          'INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?)',
          [uuid.v7(), storeId, target, role.name, active ? 1 : 0, now],
        );
      } else {
        if (existing.isEmpty) {
          throw StateError('Không tìm thấy nhân viên tại cửa hàng.');
        }
        await db.execute(
          "UPDATE users SET display_name=?,active=CASE WHEN ?='owner' THEN ? ELSE active END,updated_at=? WHERE id=?",
          [name.trim(), actor.role.name, active ? 1 : 0, now, target],
        );
        await db.execute(
          'UPDATE employee_store_assignments SET role=?,active=?,updated_at=? WHERE store_id=? AND user_id=?',
          [role.name, active ? 1 : 0, now, storeId, target],
        );
      }
      await audit(
        id == null ? 'STAFF_CREATE' : 'STAFF_UPDATE',
        'user',
        target,
        reason: reason,
        severity: 'critical',
        changes: {'name': name, 'role': role.name, 'active': active},
      );
      if (id == null && onlineStaff == null) {
        await db.execute('INSERT INTO local_settings VALUES (?,?)', [
          'grant:$target',
          clock().add(const Duration(days: 7)).toUtc().toIso8601String(),
        ]);
      }
    });
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final actor = session;
    if (actor == null) throw StateError('Vui lòng đăng nhập.');
    if (newPassword.length < 10 || oldPassword == newPassword) {
      throw ArgumentError(
        'Mật khẩu mới tối thiểu 10 ký tự và khác mật khẩu cũ.',
      );
    }
    final user = (await db.rows(
      'SELECT password_hash,salt FROM users WHERE id=?',
      [actor.userId],
    )).single;
    if (!Passwords.equal(
      await Passwords.hash(oldPassword, user['salt'] as String),
      user['password_hash'] as String,
    )) {
      throw StateError('Mật khẩu cũ không đúng.');
    }
    final salt = Passwords.salt(),
        hash = await Passwords.hash(newPassword, salt);
    if (onlinePassword != null) {
      await onlinePassword!(oldPassword, newPassword);
    }
    await db.transaction(() async {
      await db.execute(
        'UPDATE users SET password_hash=?,salt=?,must_change_password=0,updated_at=? WHERE id=?',
        [hash, salt, now, actor.userId],
      );
      await audit(
        'PASSWORD_CHANGE',
        'user',
        actor.userId,
        reason: 'Người dùng đổi mật khẩu',
        severity: 'sensitive',
      );
    });
  }
}

const roleLabels = {
  Role.owner: 'Chủ hệ thống',
  Role.manager: 'Quản lý cửa hàng',
  Role.cashier: 'Thu ngân',
  Role.warehouse: 'Nhân viên kho',
  Role.accountant: 'Kế toán',
};
