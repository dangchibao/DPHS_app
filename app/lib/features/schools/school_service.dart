import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';

extension SchoolService on LocalService {
  void requireSchoolRead() {
    final actor = session;
    if (actor == null) throw StateError('Vui lòng đăng nhập.');
    final allowed = permissionsByRole[actor.role]!;
    final permission = [
      Permission.catalog,
      Permission.sell,
      Permission.reports,
    ].where(allowed.contains).firstOrNull;
    if (permission == null) {
      throw StateError('Không có quyền xem danh mục học sinh.');
    }
    actor.require(permission, storeId, clock());
  }

  Future<Map<String, List<Map<String, Object?>>>> schoolDirectory() async {
    requireSchoolRead();
    return {
      'schools': await db.rows(
        'SELECT s.*,c.phone FROM schools s JOIN customers c ON c.id=s.customer_id AND c.store_id=s.store_id WHERE s.store_id=? ORDER BY s.name',
        [storeId],
      ),
      'classes': await db.rows(
        'SELECT c.*,s.name AS school_name FROM school_classes c JOIN schools s ON s.id=c.school_id AND s.store_id=c.store_id WHERE c.store_id=? ORDER BY c.academic_year DESC,s.name,c.name',
        [storeId],
      ),
      'students': await db.rows(
        '''SELECT st.*,c.name AS parent_name,c.phone,cl.name AS class_name,cl.academic_year,s.id AS school_id,s.name AS school_name FROM students st JOIN school_classes cl ON cl.id=st.class_id AND cl.store_id=st.store_id JOIN schools s ON s.id=cl.school_id AND s.store_id=cl.store_id JOIN customers c ON c.id=st.customer_id AND c.store_id=st.store_id WHERE st.store_id=? ORDER BY s.name,cl.name,st.name''',
        [storeId],
      ),
    };
  }

  Future<String> saveSchool({
    String? id,
    required String name,
    required String level,
    String phone = '',
    bool active = true,
  }) async {
    require(Permission.catalog);
    if (name.trim().isEmpty ||
        !['Mầm non', 'Tiểu học', 'THCS', 'THPT'].contains(level)) {
      throw ArgumentError('Nhập tên trường và cấp học hợp lệ.');
    }
    return db.transaction(() async {
      final existing = id == null
          ? <Map<String, Object?>>[]
          : await db.rows('SELECT * FROM schools WHERE store_id=? AND id=?', [
              storeId,
              id,
            ]);
      if (id != null && existing.isEmpty) {
        throw StateError('Không tìm thấy trường.');
      }
      final target = id ?? uuid.v7(),
          customer =
              existing.firstOrNull?['customer_id'] as String? ?? uuid.v7();
      await db.execute(
        "INSERT INTO customers(id,store_id,name,phone,kind,updated_at,lww_key) VALUES (?,?,?,?,'school',?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,phone=excluded.phone,updated_at=excluded.updated_at,lww_key=excluded.lww_key",
        [
          customer,
          storeId,
          name.trim(),
          phone.trim(),
          now,
          '$now|$deviceId|${uuid.v7()}',
        ],
      );
      await db.execute(
        'INSERT INTO schools VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,level=excluded.level,active=excluded.active,updated_at=excluded.updated_at,lww_key=excluded.lww_key',
        [
          target,
          storeId,
          name.trim(),
          level,
          customer,
          active ? 1 : 0,
          now,
          '$now|$deviceId|${uuid.v7()}',
        ],
      );
      await audit(
        'SCHOOL_SAVE',
        'school',
        target,
        changes: {
          'before': existing.firstOrNull,
          'after': {'name': name.trim(), 'level': level, 'active': active},
        },
      );
      await enqueue('school', {'table': 'schools', 'id': target}, 3);
      return target;
    });
  }

  Future<String> saveClass({
    String? id,
    required String schoolId,
    required String name,
    required String year,
    bool active = true,
  }) async {
    require(Permission.catalog);
    if (name.trim().isEmpty || year.trim().isEmpty) {
      throw ArgumentError('Nhập tên lớp và niên khóa.');
    }
    return db.transaction(() async {
      final school = await db.rows(
        'SELECT id FROM schools WHERE store_id=? AND id=? AND active=1',
        [storeId, schoolId],
      );
      if (school.isEmpty) {
        throw StateError('Trường không hoạt động hoặc thuộc cửa hàng khác.');
      }
      final before = id == null
          ? <Map<String, Object?>>[]
          : await db.rows(
              'SELECT * FROM school_classes WHERE store_id=? AND id=?',
              [storeId, id],
            );
      if (id != null && before.isEmpty) throw StateError('Không tìm thấy lớp.');
      final target = id ?? uuid.v7();
      await db.execute(
        'INSERT INTO school_classes VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET school_id=excluded.school_id,name=excluded.name,academic_year=excluded.academic_year,active=excluded.active,updated_at=excluded.updated_at,lww_key=excluded.lww_key',
        [
          target,
          storeId,
          schoolId,
          name.trim(),
          year.trim(),
          active ? 1 : 0,
          now,
          '$now|$deviceId|${uuid.v7()}',
        ],
      );
      await audit(
        'CLASS_SAVE',
        'class',
        target,
        changes: {
          'before': before.firstOrNull,
          'after': {
            'name': name.trim(),
            'year': year.trim(),
            'school_id': schoolId,
            'active': active,
          },
        },
      );
      await enqueue('school', {'table': 'school_classes', 'id': target}, 3);
      return target;
    });
  }

  Future<String> saveStudent({
    String? id,
    required String classId,
    required String code,
    required String name,
    required String parentName,
    String phone = '',
    bool active = true,
  }) async {
    require(Permission.catalog);
    if ([code, name, parentName].any((v) => v.trim().isEmpty)) {
      throw ArgumentError('Nhập mã học sinh, họ tên và phụ huynh.');
    }
    return db.transaction(() async {
      final classes = await db.rows(
        'SELECT cl.id FROM school_classes cl JOIN schools s ON s.id=cl.school_id AND s.store_id=cl.store_id WHERE cl.store_id=? AND cl.id=? AND cl.active=1 AND s.active=1',
        [storeId, classId],
      );
      if (classes.isEmpty) {
        throw StateError('Lớp không hoạt động hoặc thuộc cửa hàng khác.');
      }
      final before = id == null
          ? <Map<String, Object?>>[]
          : await db.rows('SELECT * FROM students WHERE store_id=? AND id=?', [
              storeId,
              id,
            ]);
      if (id != null && before.isEmpty) {
        throw StateError('Không tìm thấy học sinh.');
      }
      final target = id ?? uuid.v7(),
          customer = before.firstOrNull?['customer_id'] as String? ?? uuid.v7();
      await db.execute(
        "INSERT INTO customers VALUES (?,?,?,?,'parent',?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,phone=excluded.phone,updated_at=excluded.updated_at,lww_key=excluded.lww_key",
        [
          customer,
          storeId,
          parentName.trim(),
          phone.trim(),
          now,
          '$now|$deviceId|${uuid.v7()}',
        ],
      );
      await db.execute(
        'INSERT INTO students VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET class_id=excluded.class_id,student_code=excluded.student_code,name=excluded.name,active=excluded.active,updated_at=excluded.updated_at,lww_key=excluded.lww_key',
        [
          target,
          storeId,
          classId,
          code.trim(),
          name.trim(),
          customer,
          active ? 1 : 0,
          now,
          '$now|$deviceId|${uuid.v7()}',
        ],
      );
      await audit(
        'STUDENT_SAVE',
        'student',
        target,
        changes: {
          'before': before.firstOrNull,
          'after': {'name': name.trim(), 'class_id': classId, 'active': active},
        },
      );
      await enqueue('school', {'table': 'students', 'id': target}, 3);
      return target;
    });
  }

  Future<List<Map<String, Object?>>> studentHistory(String id) {
    requireSchoolRead();
    return db.rows(
      "SELECT id,code,total,issued_at,school_year,metadata_json FROM documents WHERE store_id=? AND json_extract(metadata_json,'\$.student_id')=? ORDER BY issued_at DESC",
      [storeId, id],
    );
  }

  Future<Map<String, Object?>> schoolSaleContext({
    String? schoolId,
    String? studentId,
    String? customerId,
  }) async {
    requireSchoolRead();
    final context = <String, Object?>{};
    if (studentId != null) {
      final rows = await db.rows(
        '''SELECT st.id,st.name,st.customer_id,cl.name AS class_name,cl.academic_year,s.id AS school_id,s.name AS school_name FROM students st JOIN school_classes cl ON cl.id=st.class_id AND cl.store_id=st.store_id JOIN schools s ON s.id=cl.school_id AND s.store_id=cl.store_id WHERE st.store_id=? AND st.id=? AND st.active=1 AND cl.active=1 AND s.active=1''',
        [storeId, studentId],
      );
      if (rows.isEmpty) {
        throw StateError('Học sinh/lớp/trường đã ngừng hoạt động.');
      }
      final st = rows.single;
      context.addAll({
        'student_id': studentId,
        'student_name': st['name'],
        'class_name': st['class_name'],
        'academic_year': st['academic_year'],
        'school_id': st['school_id'],
        'school_name': st['school_name'],
      });
      customerId = st['customer_id'] as String;
    } else if (schoolId != null) {
      final rows = await db.rows(
        'SELECT name,customer_id FROM schools WHERE store_id=? AND id=? AND active=1',
        [storeId, schoolId],
      );
      if (rows.isEmpty) throw StateError('Trường đã ngừng hoạt động.');
      context.addAll({
        'school_id': schoolId,
        'school_name': rows.single['name'],
        'group_order': true,
      });
      customerId = rows.single['customer_id'] as String;
    }
    if (customerId != null) {
      final rows = await db.rows(
        'SELECT name,phone,kind FROM customers WHERE store_id=? AND id=?',
        [storeId, customerId],
      );
      if (rows.isEmpty) {
        throw StateError('Khách hàng thuộc cửa hàng khác hoặc không tồn tại.');
      }
      context.addAll({
        'customer_id': customerId,
        'customer_name': rows.single['name'],
        'phone': rows.single['phone'],
        'customer_kind': rows.single['kind'],
      });
    }
    return context;
  }
}
