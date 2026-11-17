import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'auth/password.dart';
import 'auth/audit_redaction.dart';
import 'app_version.dart';
import 'auth/permissions.dart';
import 'database/database.dart';
import 'sync/sync_engine.dart';
import 'sync/cloud_api.dart';
import 'backup/backup_service.dart';

class LocalService {
  LocalService(
    this.db, {
    DateTime Function()? clock,
    this.storeId = defaultStoreId,
    this.deviceId = defaultDeviceId,
  }) : clock = clock ?? DateTime.now;
  final AppDatabase db;
  final DateTime Function() clock;
  static const defaultStoreId = 'store-cn01', defaultDeviceId = 'device-a2';
  final String storeId, deviceId;
  final Uuid uuid = const Uuid();
  String get now => DateTime.fromMillisecondsSinceEpoch(
    clock().millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
  LocalSession? session;
  String installationHash = '';
  bool restoreBlocked = false;
  bool maintenance = false;
  BackupService? backup;
  BackupScheduler? backupScheduler;
  SyncEngine? syncEngine;
  Future<Map<String, Object?>?> Function(String, String)? onlineLogin;
  Future<Map<String, Object?>> Function(Map<String, Object?>)? onlineStaff;
  Future<Map<String, Object?>> Function(String, String)? onlinePassword;
  void Function()? onQueue;
  Future<bool> get initialized async =>
      (await db.rows('SELECT id FROM users LIMIT 1')).isNotEmpty ||
      (await db.rows(
        "SELECT value FROM local_settings WHERE key='enrolled' AND value='1'",
      )).isNotEmpty;

  Future<void> bootstrap(String password) async {
    if (password.length < 10) {
      throw ArgumentError('Mật khẩu tối thiểu 10 ký tự.');
    }
    final salt = Passwords.salt(), hash = await Passwords.hash(password, salt);
    await db.transaction(() async {
      if (await initialized) throw StateError('Thiết bị đã được khởi tạo.');
      await db.execute('INSERT INTO stores VALUES (?,?,?,?,?)', [
        storeId,
        'NT-CN01',
        'Ngọc Thanh · Chi nhánh 01',
        1,
        now,
      ]);
      await db.execute(
        'INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES (?,?,?,?,?,?)',
        [deviceId, storeId, 'A2', 'Máy bán hàng A2', 'approved', now],
      );
      await db.execute('INSERT INTO users VALUES (?,?,?,?,?,?,?,?)', [
        'admin',
        'admin',
        'Chủ hệ thống',
        hash,
        salt,
        1,
        1,
        now,
      ]);
      await db.execute(
        'INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?)',
        [uuid.v7(), storeId, 'admin', 'owner', 1, now],
      );
      await db.execute('INSERT INTO local_settings VALUES (?,?)', [
        'grant:admin',
        clock().add(const Duration(days: 7)).toUtc().toIso8601String(),
      ]);
      if (installationHash.isNotEmpty) {
        await db.execute(
          "INSERT INTO local_settings VALUES ('installation_hash',?)",
          [installationHash],
        );
      }
      session = LocalSession(
        userId: 'admin',
        name: 'Chủ hệ thống',
        role: Role.owner,
        storeId: storeId,
        deviceId: deviceId,
        expiresAt: clock().add(const Duration(days: 7)),
        mustChangePassword: true,
      );
      await audit(
        'SYSTEM_BOOTSTRAP',
        'system',
        storeId,
        reason: 'Khởi tạo thiết bị local',
        severity: 'critical',
      );
      for (final item in [
        ('Áo sơ mi trắng', 'Áo sơ mi', 125000, 75000),
        ('Quần tây xanh', 'Váy / quần', 145000, 85000),
        ('Áo khoác mùa đông', 'Áo khoác', 235000, 150000),
        ('Mũ đồng phục', 'Mũ', 45000, 25000),
        ('Giày học sinh', 'Giày', 195000, 120000),
      ]) {
        final productId = uuid.v7();
        await db.execute(
          'INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES (?,?,?,?,?,?,?)',
          [productId, item.$1, item.$2, 'Unisex', 'Tiểu học', '2026–2027', now],
        );
        for (final size in ['S', 'M', 'L']) {
          final variantId = uuid.v7();
          final sku = 'NT-${item.$2.hashCode.abs()}-$size';
          await db.execute(
            'INSERT INTO product_variants(id,product_id,sku,barcode,size,color,unit,cost,price,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
            [
              variantId,
              productId,
              sku,
              sku,
              size,
              'Mặc định',
              'cái',
              item.$4,
              item.$3,
              now,
            ],
          );
          await db.execute(
            'INSERT INTO stock_movements VALUES (?,?,?,?,?,?,?,?,?,?)',
            [
              uuid.v7(),
              storeId,
              deviceId,
              variantId,
              20,
              'receipt',
              null,
              'Tồn đầu dữ liệu mẫu',
              'admin',
              now,
            ],
          );
        }
      }
      await enqueue('bootstrap', {'store_id': storeId}, -1);
      for (final entry in [
        ('Tiểu học mẫu Ngọc Thanh', 'Tiểu học', '1A', '01'),
        ('THCS mẫu Ngọc Thanh', 'THCS', '6A', '02'),
      ]) {
        final school = uuid.v7(),
            schoolClass = uuid.v7(),
            student = uuid.v7(),
            schoolCustomer = uuid.v7(),
            parent = uuid.v7();
        await db.execute('INSERT INTO customers VALUES (?,?,?,?,?,?,?)', [
          schoolCustomer,
          storeId,
          entry.$1,
          '',
          'school',
          now,
          '',
        ]);
        await db.execute('INSERT INTO customers VALUES (?,?,?,?,?,?,?)', [
          parent,
          storeId,
          'Phụ huynh mẫu ${entry.$4}',
          '',
          'parent',
          now,
          '',
        ]);
        await db.execute('INSERT INTO schools VALUES (?,?,?,?,?,?,?,?)', [
          school,
          storeId,
          entry.$1,
          entry.$2,
          schoolCustomer,
          1,
          now,
          '',
        ]);
        await db.execute(
          'INSERT INTO school_classes VALUES (?,?,?,?,?,?,?,?)',
          [schoolClass, storeId, school, entry.$3, '2026–2027', 1, now, ''],
        );
        await db.execute('INSERT INTO students VALUES (?,?,?,?,?,?,?,?,?)', [
          student,
          storeId,
          schoolClass,
          'HS-MAU-${entry.$4}',
          'Học sinh mẫu ${entry.$4}',
          parent,
          1,
          now,
          '',
        ]);
        await audit(
          'SCHOOL_SEED',
          'school',
          school,
          changes: {
            'school_name': entry.$1,
            'class_name': entry.$3,
            'student_code': 'HS-MAU-${entry.$4}',
          },
        );
        await enqueue('school', {'table': 'schools', 'id': school}, 3);
        await enqueue('school', {
          'table': 'school_classes',
          'id': schoolClass,
        }, 3);
        await enqueue('school', {'table': 'students', 'id': student}, 3);
      }
      final shirts = await db.rows(
        "SELECT id FROM products WHERE category='Áo sơ mi' ORDER BY id LIMIT 1",
      );
      final trousers = await db.rows(
        "SELECT id FROM products WHERE category='Váy / quần' ORDER BY id LIMIT 1",
      );
      final combo = uuid.v7();
      await db.execute('INSERT INTO combo_rules VALUES (?,?,?,?,?,?,?,?)', [
        combo,
        storeId,
        'Bộ chính khóa mẫu',
        250000,
        jsonEncode([
          {'product_id': shirts.single['id'], 'quantity': 1},
          {'product_id': trousers.single['id'], 'quantity': 1},
        ]),
        1,
        now,
        '',
      ]);
      await audit(
        'COMBO_SAVE',
        'combo',
        combo,
        reason: 'Khởi tạo combo mẫu',
        changes: {'name': 'Bộ chính khóa mẫu', 'price': 250000},
      );
      await enqueue('combo', {'id': combo}, 3);
    });
    session = null;
  }

  Future<LocalSession> login(String username, String password) async {
    Map<String, Object?>? remote;
    try {
      remote = await onlineLogin?.call(username.trim(), password);
    } on CloudError catch (error) {
      if (error.code == 'DEVICE_IDENTITY') {
        restoreBlocked = true;
        await db.execute(
          "INSERT INTO local_settings VALUES ('restore_blocked','1') ON CONFLICT(key) DO UPDATE SET value='1'",
        );
        await db.execute(
          "INSERT INTO local_settings VALUES ('restore_reason','identity') ON CONFLICT(key) DO UPDATE SET value='identity'",
        );
      }
      if (error.status == 401) {
        final cached = await db.rows(
          'SELECT u.id,u.password_hash,u.salt FROM users u JOIN employee_store_assignments a ON a.user_id=u.id WHERE u.username=? AND a.store_id=?',
          [username.trim(), storeId],
        );
        if (cached.isNotEmpty) {
          final user = cached.single;
          final matches =
              error.code == 'CREDENTIAL_CHANGED' ||
              ((user['password_hash'] as String).isNotEmpty &&
                  Passwords.equal(
                    await Passwords.hash(password, user['salt'] as String),
                    user['password_hash'] as String,
                  ));
          if (matches) {
            await db.execute('DELETE FROM local_settings WHERE key=?', [
              'grant:${user['id']}',
            ]);
          }
        }
      }
      rethrow;
    }
    if (remote != null) {
      final expiresAt = remote['expires_at'];
      final user = Map<String, Object?>.from(remote['user'] as Map);
      final salt = Passwords.salt(),
          hash = await Passwords.hash(password, salt);
      await db.transaction(() async {
        // Đăng nhập API thành công xác nhận máy pending đã được chủ duyệt.
        await db.execute(
          "UPDATE devices SET status='approved' WHERE store_id=? AND id=? AND status='pending'",
          [storeId, deviceId],
        );
        await db.execute(
          'INSERT INTO users VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name,password_hash=excluded.password_hash,salt=excluded.salt,active=1,must_change_password=excluded.must_change_password,updated_at=excluded.updated_at',
          [
            user['id'],
            username.trim(),
            user['name'],
            hash,
            salt,
            1,
            user['must_change_password'] == true ? 1 : 0,
            now,
          ],
        );
        await db.execute(
          'INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?) ON CONFLICT(store_id,user_id) DO UPDATE SET role=excluded.role,active=1,updated_at=excluded.updated_at',
          [uuid.v7(), storeId, user['id'], user['role'], 1, now],
        );
        await db.execute(
          'INSERT INTO local_settings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          ['grant:${user['id']}', expiresAt],
        );
      });
    }
    final matches = await db.rows(
      'SELECT u.*,a.role FROM users u JOIN employee_store_assignments a ON a.user_id=u.id WHERE u.username=? AND u.active=1 AND a.store_id=? AND a.active=1',
      [username.trim(), storeId],
    );
    final user = matches.isEmpty ? null : matches.first;
    final valid =
        user != null &&
        (remote != null ||
            Passwords.equal(
              await Passwords.hash(password, user['salt'] as String),
              user['password_hash'] as String,
            ));
    if (!valid) {
      await db.transaction(() async {
        await audit(
          'LOGIN_FAILED',
          'user',
          'unknown',
          reason: 'Sai thông tin đăng nhập',
          actor: null,
        );
      });
      throw StateError('Tài khoản hoặc mật khẩu không đúng.');
    }
    final device = await db.rows(
      'SELECT status FROM devices WHERE store_id=? AND id=?',
      [storeId, deviceId],
    );
    if (device.isEmpty || device.first['status'] != 'approved') {
      throw StateError('Thiết bị chưa được duyệt hoặc đã thu hồi.');
    }
    final grants = await db.rows(
      'SELECT value FROM local_settings WHERE key=?',
      ['grant:${user['id']}'],
    );
    if (grants.isEmpty ||
        !DateTime.parse(grants.single['value'] as String).isAfter(clock())) {
      throw StateError(
        'Quyền offline hết hạn. Vui lòng kết nối cloud để đăng nhập.',
      );
    }
    session = LocalSession(
      userId: user['id'] as String,
      name: user['display_name'] as String,
      role: Role.values.byName(user['role'] as String),
      storeId: storeId,
      deviceId: deviceId,
      expiresAt: DateTime.parse(grants.single['value'] as String),
      mustChangePassword: user['must_change_password'] == 1,
    );
    await db.transaction(() async {
      await db.execute(
        "INSERT INTO local_settings VALUES ('last_authenticated_user',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [session!.userId],
      );
      await audit('LOGIN_SUCCESS', 'user', session!.userId);
    });
    return session!;
  }

  Future<void> acceptOnlineReconnect(Map<String, Object?> remote) async {
    final old = session,
        user = Map<String, Object?>.from(remote['user'] as Map);
    if (old == null ||
        user['id'] != old.userId ||
        remote['store_id'] != storeId ||
        remote['device_id'] != deviceId) {
      throw const CloudError(
        401,
        'IDENTITY_CHANGED',
        'Danh tính đăng nhập thay đổi. Vui lòng đăng nhập lại.',
      );
    }
    final role = Role.values.byName(user['role'] as String),
        expires = DateTime.parse(remote['expires_at'] as String);
    await db.transaction(() async {
      await db.execute(
        'UPDATE users SET display_name=?,active=1,must_change_password=?,updated_at=? WHERE id=?',
        [
          user['name'],
          user['must_change_password'] == true ? 1 : 0,
          now,
          old.userId,
        ],
      );
      await db.execute(
        'UPDATE employee_store_assignments SET role=?,active=1,updated_at=? WHERE store_id=? AND user_id=?',
        [role.name, now, storeId, old.userId],
      );
      await db.execute(
        'INSERT INTO local_settings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        ['grant:${old.userId}', expires.toUtc().toIso8601String()],
      );
    });
    session = LocalSession(
      userId: old.userId,
      name: user['name'] as String,
      role: role,
      storeId: storeId,
      deviceId: deviceId,
      expiresAt: expires,
      mustChangePassword: user['must_change_password'] == true,
    );
  }

  LocalSession require(Permission permission) {
    if (maintenance && permission != Permission.backup) {
      throw StateError('Thiết bị đang khôi phục dữ liệu. Vui lòng chờ.');
    }
    if (restoreBlocked &&
        [
          Permission.sell,
          Permission.collect,
          Permission.stock,
          Permission.catalog,
          Permission.staff,
          Permission.payroll,
          Permission.tailoring,
          Permission.returns,
          Permission.voidInvoice,
          Permission.configure,
          Permission.reserve,
          Permission.attendance,
        ].contains(permission)) {
      throw StateError(
        'Cần đồng bộ và đối soát dữ liệu sau khôi phục trước khi tiếp tục thao tác.',
      );
    }
    final active = session;
    if (active == null) throw StateError('Vui lòng đăng nhập.');
    active.require(permission, storeId, clock());
    return active;
  }

  Future<List<Map<String, Object?>>> catalog({String search = ''}) {
    final actor = session;
    if (actor == null) throw StateError('Vui lòng đăng nhập.');
    if (!(permissionsByRole[actor.role]!.any(
      (p) => [
        Permission.sell,
        Permission.catalog,
        Permission.stock,
        Permission.reports,
      ].contains(p),
    ))) {
      throw StateError('Bạn không có quyền xem sản phẩm.');
    }
    actor.require(
      permissionsByRole[actor.role]!.contains(Permission.sell)
          ? Permission.sell
          : permissionsByRole[actor.role]!.contains(Permission.stock)
          ? Permission.stock
          : permissionsByRole[actor.role]!.contains(Permission.catalog)
          ? Permission.catalog
          : Permission.reports,
      storeId,
      clock(),
    );
    return db.rows(
      '''WITH held AS (SELECT r.variant_id,SUM(r.quantity) AS reserved,SUM(CASE WHEN r.device_id=? THEN r.quantity ELSE 0 END) AS device_reserved
      FROM reservation_lines r WHERE r.store_id=? AND r.created_at<=? AND r.expires_at>?
      AND NOT EXISTS(SELECT 1 FROM reservation_events e WHERE e.store_id=r.store_id AND e.document_id=r.document_id AND e.created_at<=?) GROUP BY r.variant_id)
      SELECT v.*,p.name,p.category,p.gender,p.school_level,p.school_year,p.image_path,COALESCE(b.quantity,0) AS stock,
      COALESCE(h.reserved,0) AS reserved,COALESCE(b.quantity,0)-COALESCE(h.reserved,0) AS available,
      COALESCE(a.quantity,0)-COALESCE(h.device_reserved,0) AS device_available,
      COALESCE(s.price_override,v.price) AS sale_price, COALESCE(s.low_stock_threshold,5) AS threshold
      FROM product_variants v JOIN products p ON p.id=v.product_id
      LEFT JOIN stock_balances b ON b.variant_id=v.id AND b.store_id=?
      LEFT JOIN store_variant_settings s ON s.variant_id=v.id AND s.store_id=?
      LEFT JOIN held h ON h.variant_id=v.id
      LEFT JOIN device_stock_allocations a ON a.store_id=? AND a.device_id=? AND a.variant_id=v.id
      WHERE p.active=1 AND v.active=1 AND (p.name LIKE ? OR v.barcode=? OR v.sku LIKE ?) ORDER BY p.name,v.size''',
      [
        deviceId,
        storeId,
        now,
        now,
        now,
        storeId,
        storeId,
        storeId,
        deviceId,
        '%$search%',
        search,
        '%$search%',
      ],
    );
  }

  Future<void> addProduct({
    required String name,
    required String category,
    required String size,
    required String color,
    required String barcode,
    required int price,
    required int cost,
  }) async {
    require(Permission.catalog);
    if (name.trim().isEmpty ||
        size.trim().isEmpty ||
        color.trim().isEmpty ||
        barcode.trim().isEmpty ||
        price < 0 ||
        cost < 0) {
      throw ArgumentError('Thông tin sản phẩm không hợp lệ.');
    }
    await db.transaction(() async {
      final product = uuid.v7(), variant = uuid.v7();
      await db.execute(
        'INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES (?,?,?,?,?,?,?)',
        [
          product,
          name.trim(),
          category,
          'Unisex',
          'Tiểu học',
          '2026–2027',
          now,
        ],
      );
      await db.execute(
        'INSERT INTO product_variants(id,product_id,sku,barcode,size,color,unit,cost,price,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          variant,
          product,
          barcode.trim(),
          barcode.trim(),
          size.trim(),
          color.trim(),
          'cái',
          cost,
          price,
          now,
        ],
      );
      await audit(
        'PRODUCT_CREATE',
        'product',
        product,
        changes: {'name': name, 'price': price},
      );
      await enqueue('catalog', {
        'product_id': product,
        'variant_id': variant,
      }, 3);
    });
  }

  Future<void> adjustStock(
    String variant,
    int quantity,
    String reason, {
    String kind = 'adjustment',
  }) async {
    final actor = require(Permission.stock);
    if (!['receipt', 'adjustment'].contains(kind) ||
        (kind == 'receipt' && quantity <= 0)) {
      throw ArgumentError('Loại nhập/điều chỉnh kho không hợp lệ.');
    }
    if (quantity == 0 || reason.trim().isEmpty) {
      throw ArgumentError('Nhập số lượng khác 0 và lý do.');
    }
    await db.transaction(() async {
      final rows = await db.rows(
        'SELECT quantity FROM stock_balances WHERE store_id=? AND variant_id=?',
        [storeId, variant],
      );
      final before = rows.isEmpty ? 0 : rows.first['quantity'] as int;
      if (before + quantity < 0) throw StateError('Không đủ tồn kho.');
      final id = uuid.v7();
      await db.execute(
        'INSERT INTO stock_movements VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          storeId,
          deviceId,
          variant,
          quantity,
          kind,
          null,
          reason.trim(),
          actor.userId,
          now,
        ],
      );
      await audit(
        'STOCK_ADJUST',
        'variant',
        variant,
        reason: reason,
        severity: 'critical',
        changes: {'before': before, 'after': before + quantity},
      );
      await enqueue('stock_movement', {'id': id}, 0);
    });
  }

  Future<void> rebuildStockCache() async {
    require(Permission.stock);
    await db.transaction(() async {
      await db.execute('DELETE FROM stock_balances WHERE store_id=?', [
        storeId,
      ]);
      await db.execute(
        'INSERT INTO stock_balances SELECT store_id,variant_id,SUM(quantity) FROM stock_movements WHERE store_id=? GROUP BY store_id,variant_id',
        [storeId],
      );
      await audit(
        'STOCK_REBUILD',
        'store',
        storeId,
        reason: 'Dựng lại số dư từ sổ cái',
      );
    });
  }

  Future<void> audit(
    String action,
    String type,
    String entity, {
    String reason = '',
    String severity = 'normal',
    Map<String, Object?> changes = const {},
    LocalSession? actor,
    String? documentCode,
  }) async {
    if (severity == 'critical' && reason.trim().isEmpty) {
      throw StateError('Thao tác nghiêm trọng cần lý do.');
    }
    changes = redactAuditChanges(changes, action: action);
    final previous = await db.rows(
      'SELECT hash,chain_index FROM audit_logs WHERE store_id=? AND device_id=? AND chain_index>0 ORDER BY chain_index DESC LIMIT 1',
      [storeId, deviceId],
    );
    final prev = previous.isEmpty ? '' : previous.first['hash'] as String;
    final index = previous.isEmpty
        ? 1
        : (previous.first['chain_index'] as int) + 1;
    final current = actor ?? session;
    if (documentCode == null && type == 'document') {
      final documents = await db.rows(
        'SELECT code FROM documents WHERE store_id=? AND id=?',
        [storeId, entity],
      );
      if (documents.isNotEmpty) {
        documentCode = documents.single['code'] as String;
      }
    }
    final id = uuid.v7(), time = now;
    final payload = {
      'id': id,
      'store_id': storeId,
      'device_id': deviceId,
      'user_id': current?.userId,
      'role': current?.role.name ?? 'anonymous',
      'action': action,
      'entity_type': type,
      'entity_id': entity,
      'changes': changes,
      'reason': reason,
      'client_time': time,
      'severity': severity,
      'hash_prev': prev,
      'chain_index': index,
    };
    final hash = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    await db.execute(
      'INSERT INTO audit_logs VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        storeId,
        deviceId,
        current?.userId,
        current?.role.name ?? 'anonymous',
        action,
        type,
        entity,
        documentCode,
        jsonEncode(changes),
        reason,
        time,
        null,
        appVersion,
        severity,
        prev,
        hash,
        index,
      ],
    );
    await enqueue('audit', {'id': id}, 1);
  }

  Future<void> enqueue(
    String type,
    Map<String, Object?> payload,
    int priority,
  ) async {
    final id = uuid.v7();
    final records = <Map<String, Object?>>[];
    Future<void> collect(
      String table,
      String clause,
      List<Object?> args,
    ) async {
      for (final row in await db.rows(
        'SELECT * FROM $table WHERE $clause',
        args,
      )) {
        if (table == 'products' ||
            table == 'product_variants' ||
            table == 'customers' ||
            [
              'schools',
              'school_classes',
              'students',
              'combo_rules',
              'commercial_rules',
              'tailoring_rules',
              'size_rules',
            ].contains(table)) {
          row['lww_key'] = '${row['updated_at']}|$deviceId|$id';
          await db.execute('UPDATE $table SET lww_key=? WHERE id=?', [
            row['lww_key'],
            row['id'],
          ]);
        }
        records.add({'table': table, 'row': row});
      }
    }

    if (type == 'bootstrap') {
      await collect('products', '1=1', []);
      await collect('product_variants', '1=1', []);
      await collect('stock_movements', 'store_id=?', [storeId]);
    } else if (type == 'catalog') {
      await collect('products', 'id=?', [payload['product_id']]);
      await collect('product_variants', 'id=?', [payload['variant_id']]);
    } else if (type == 'stock_movement') {
      await collect('stock_movements', 'id=?', [payload['id']]);
    } else if (type == 'audit') {
      await collect('audit_logs', 'id=?', [payload['id']]);
    } else if (type == 'payroll_command') {
      await collect('payroll_commands', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'attendance') {
      await collect('attendance_entries', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'payment') {
      await collect('payments', 'id=?', [payload['id']]);
      await collect('receivable_entries', 'payment_id=?', [payload['id']]);
    } else if (type == 'size_rule') {
      await collect('size_rules', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'tailoring_rule') {
      await collect('tailoring_rules', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'tailoring_event') {
      await collect('document_events', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'dealer') {
      await collect('customers', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'commercial') {
      await collect('commercial_rules', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'combo') {
      await collect('combo_rules', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'school') {
      final table = payload['table'] as String;
      if (!['schools', 'school_classes', 'students'].contains(table)) {
        throw ArgumentError('Danh mục trường không hợp lệ.');
      }
      if (table == 'schools' || table == 'students') {
        await collect(
          'customers',
          'id IN (SELECT customer_id FROM $table WHERE store_id=? AND id=?)',
          [storeId, payload['id']],
        );
      }
      await collect(table, 'store_id=? AND id=?', [storeId, payload['id']]);
    } else if (type == 'return') {
      if (payload['new_customer'] == true) {
        await collect(
          'customers',
          'id IN (SELECT customer_id FROM documents WHERE id=?)',
          [payload['id']],
        );
      }
      await collect('documents', 'id=?', [payload['id']]);
      await collect('return_lines', 'document_id=?', [payload['id']]);
      await collect('invoice_lines', 'document_id=?', [payload['id']]);
      await collect('payments', 'document_id=?', [payload['id']]);
      await collect('receivable_entries', 'document_id=?', [payload['id']]);
      await collect('receivable_adjustments', 'credit_document_id=?', [
        payload['id'],
      ]);
      await collect(
        'stock_movements',
        "document_id=? ORDER BY CASE WHEN kind='return' THEN 0 ELSE 1 END,id",
        [payload['id']],
      );
      await collect('document_events', "related_id=? AND type='CANCELLED'", [
        payload['id'],
      ]);
    } else if (type == 'transfer_dispatch') {
      await collect('transfer_events', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'transfer_out' || type == 'transfer_in') {
      await collect('documents', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
      await collect('invoice_lines', 'store_id=? AND document_id=?', [
        storeId,
        payload['id'],
      ]);
      await collect('transfer_receipts', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
      await collect('stock_movements', 'store_id=? AND document_id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'reservation_event') {
      await collect('reservation_events', 'store_id=? AND id=?', [
        storeId,
        payload['id'],
      ]);
    } else if (type == 'sale' || type == 'tailoring' || type == 'reservation') {
      await collect(
        'customers',
        'id IN (SELECT customer_id FROM documents WHERE id=?)',
        [payload['id']],
      );
      await collect('documents', 'id=?', [payload['id']]);
      await collect('invoice_lines', 'document_id=?', [payload['id']]);
      await collect('reservation_lines', 'document_id=?', [payload['id']]);
      await collect('reservation_events', 'related_document_id=?', [
        payload['id'],
      ]);
      await collect('payments', 'document_id=?', [payload['id']]);
      await collect('receivable_entries', 'document_id=?', [payload['id']]);
      await collect('stock_movements', 'document_id=?', [payload['id']]);
    }
    if (records.isEmpty) {
      throw StateError('Không có dữ liệu cho hàng đợi $type.');
    }
    if (records.length > 100 ||
        utf8.encode(jsonEncode(records)).length > 190000) {
      throw StateError(
        'Chứng từ vượt dung lượng đồng bộ đã cấu hình. Vui lòng chia thành các chứng từ nhỏ hơn.',
      );
    }
    final dependencies = <String>{};
    if (['transfer_out', 'transfer_in', 'transfer_dispatch'].contains(type)) {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type IN ('transfer_out','transfer_in','transfer_dispatch','catalog','sale','return','stock_movement','reservation','reservation_event')",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (type == 'size_rule') {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type='catalog'",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if ([
      'reservation',
      'reservation_event',
      'sale',
      'return',
      'stock_movement',
      'transfer_out',
      'transfer_in',
    ].contains(type)) {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type IN ('reservation','reservation_event','sale','return','stock_movement','catalog','school','transfer_out','transfer_in')",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (type == 'return') {
      dependencies.addAll(
        (await db.rows(
          "SELECT DISTINCT o.id FROM outbox o,json_each(o.payload) j WHERE o.store_id=? AND ((o.entity_type IN ('sale','tailoring','return') AND json_extract(j.value,'\$.table')='documents' AND json_extract(j.value,'\$.row.id')=?) OR (o.entity_type='payment' AND json_extract(j.value,'\$.table')='payments' AND json_extract(j.value,'\$.row.document_id')=?))",
          [storeId, payload['original_id'], payload['original_id']],
        )).map((r) => r['id'] as String),
      );
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type='return'",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (type == 'tailoring' || type == 'tailoring_rule') {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type IN ('tailoring_rule','catalog')",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (type == 'tailoring_event') {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type IN ('tailoring','tailoring_event')",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (['commercial', 'dealer', 'sale', 'tailoring'].contains(type)) {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type IN ('commercial','dealer')",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (type == 'commercial') {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type IN ('catalog','school')",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (type == 'combo' || type == 'sale') {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type='combo'",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (type == 'combo') {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type='catalog'",
          [storeId],
        )).map((r) => r['id'] as String),
      );
    }
    if (type == 'school' || type == 'sale' || type == 'tailoring') {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type='school'",
          [storeId],
        )).map((e) => e['id'] as String),
      );
    }
    if (type == 'payment') {
      final payment =
          records.firstWhere((r) => r['table'] == 'payments')['row']
              as Map<String, Object?>;
      dependencies.addAll(
        (await db.rows(
          "SELECT DISTINCT o.id FROM outbox o,json_each(o.payload) j WHERE o.store_id=? AND o.entity_type IN ('sale','tailoring') AND json_extract(j.value,'\$.table')='documents' AND json_extract(j.value,'\$.row.id')=?",
          [storeId, payment['document_id']],
        )).map((e) => e['id'] as String),
      );
    }
    if (type != 'bootstrap' && type != 'audit') {
      dependencies.addAll(
        (await db.rows(
          "SELECT id FROM outbox WHERE store_id=? AND entity_type='bootstrap'",
          [storeId],
        )).map((e) => e['id'] as String),
      );
    }
    if (type == 'stock_movement' || type == 'sale' || type == 'return') {
      for (final record in records.where(
        (r) => r['table'] == 'stock_movements',
      )) {
        final variant = record['row'] as Map<String, Object?>;
        dependencies.addAll(
          (await db.rows(
            "SELECT DISTINCT o.id FROM outbox o,json_each(o.payload) j WHERE o.store_id=? AND o.entity_type='catalog' AND json_extract(j.value,'\$.row.id')=?",
            [storeId, variant['variant_id']],
          )).map((e) => e['id'] as String),
        );
        dependencies.addAll(
          (await db.rows(
            "SELECT DISTINCT o.id FROM outbox o,json_each(o.payload) j WHERE o.store_id=? AND o.entity_type='stock_movement' AND json_extract(j.value,'\$.table')='stock_movements' AND json_extract(j.value,'\$.row.variant_id')=?",
            [storeId, variant['variant_id']],
          )).map((e) => e['id'] as String),
        );
      }
    }
    await db.execute(
      'INSERT INTO outbox(id,store_id,device_id,entity_type,payload,priority,created_at,dependencies_json,actor_id) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        id,
        storeId,
        deviceId,
        type,
        jsonEncode(records),
        priority,
        now,
        jsonEncode(dependencies.toList()),
        session?.userId ??
            (await db.rows(
              "SELECT value FROM local_settings WHERE key='last_authenticated_user'",
            )).firstOrNull?['value'] ??
            'admin',
      ],
    );
    onQueue?.call();
  }
}
