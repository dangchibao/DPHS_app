import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/schools/school_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalService service;
  setUp(() async {
    service = await salesFixture();
  });
  tearDown(() async {
    await service.db.close();
  });
  Future<(String, String, String)> student() async {
    final school = await service.saveSchool(
      name: 'Tiểu học Ngọc Thanh',
      level: 'Tiểu học',
    );
    final cl = await service.saveClass(
      schoolId: school,
      name: '2A',
      year: '2027–2028',
    );
    final st = await service.saveStudent(
      classId: cl,
      code: 'HS001',
      name: 'Nguyễn An',
      parentName: 'Phụ huynh An',
      phone: '0900000000',
    );
    return (school, cl, st);
  }

  test(
    'Gắn học sinh, tái dùng phụ huynh và giữ snapshot khi danh mục đổi',
    () async {
      final ids = await student();
      final sale = await service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 50000,
        method: 'cash',
        studentId: ids.$3,
      );
      final invoice = (await service.db.rows('SELECT * FROM documents')).single;
      final old = jsonDecode(invoice['metadata_json'] as String) as Map;
      expect(invoice['school_year'], '2027–2028');
      expect(old['student_name'], 'Nguyễn An');
      expect(old['school_name'], 'Tiểu học Ngọc Thanh');
      await service.saveSchool(
        id: ids.$1,
        name: 'Trường đổi tên',
        level: 'Tiểu học',
      );
      await service.saveStudent(
        id: ids.$3,
        classId: ids.$2,
        code: 'HS001',
        name: 'Nguyễn An',
        parentName: 'Phụ huynh đổi tên',
        phone: '0911111111',
      );
      final second = await service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 100000,
        method: 'cash',
        studentId: ids.$3,
      );
      expect(await service.studentHistory(ids.$3), hasLength(2));
      final invoices = await service.db.rows(
        'SELECT customer_id,metadata_json FROM documents WHERE id IN (?,?)',
        [sale.id, second.id],
      );
      expect(invoices.map((r) => r['customer_id']).toSet(), hasLength(1));
      expect(
        jsonDecode(
          (await service.db.rows(
                'SELECT metadata_json FROM documents WHERE id=?',
                [sale.id],
              )).single['metadata_json']
              as String,
        )['school_name'],
        'Tiểu học Ngọc Thanh',
      );
      expect(
        (await service.schoolDirectory())['students']!.single['parent_name'],
        'Phụ huynh đổi tên',
      );
    },
  );
  test('Đơn tập thể gắn công nợ đúng khách trường; từ chối tham chiếu ngoài cửa hàng', () async {
    final school = await service.saveSchool(
      name: 'THCS Ngọc Thanh',
      level: 'THCS',
    );
    final sale = await service.sell(
      items: [const CartItem('v1', 2)],
      discount: 0,
      received: 50000,
      method: 'bank',
      schoolId: school,
    );
    final row = (await service.db.rows(
      'SELECT c.kind,r.amount FROM receivable_entries r JOIN customers c ON c.id=r.customer_id WHERE r.document_id=?',
      [sale.id],
    )).single;
    expect(row, {'kind': 'school', 'amount': 150000});
    await expectLater(
      service.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 0,
        method: 'cash',
        schoolId: 'foreign-school',
      ),
      throwsStateError,
    );
    expect(await service.db.rows('SELECT * FROM documents'), hasLength(1));
  });
  test('Mã học sinh trùng rollback cả khách hàng, audit và outbox; thu ngân chỉ được đọc', () async {
    final ids = await student();
    final before = (await service.db.rows(
      'SELECT COUNT(*) AS n FROM customers',
    )).single['n'];
    final jobs = (await service.db.rows('SELECT COUNT(*) AS n FROM outbox'))
        .single['n'];
    await expectLater(
      service.saveStudent(
        classId: ids.$2,
        code: 'HS001',
        name: 'Trùng mã',
        parentName: 'Phụ huynh khác',
      ),
      throwsA(anything),
    );
    expect(
      (await service.db.rows('SELECT COUNT(*) AS n FROM customers'))
          .single['n'],
      before,
    );
    expect(
      (await service.db.rows('SELECT COUNT(*) AS n FROM outbox')).single['n'],
      jobs,
    );
    final owner = service.session!;
    service.session = LocalSession(
      userId: owner.userId,
      name: owner.name,
      role: Role.cashier,
      storeId: owner.storeId,
      deviceId: owner.deviceId,
      expiresAt: owner.expiresAt,
    );
    expect((await service.schoolDirectory())['students'], hasLength(1));
    await expectLater(
      service.saveSchool(name: 'Không được phép', level: 'THCS'),
      throwsStateError,
    );
  });
  test('Tổng tiền dùng BigInt, không chấp nhận tràn số nguyên khi nhân số lượng lớn', () async {
    await service.adjustStock('v1', 99990, 'Chuẩn bị kiểm thử giới hạn');
    await service.db.execute(
      "UPDATE product_variants SET price=9007199254740991,lww_key='2026-11-15T00:00:00.000Z|A2|large' WHERE id='v1'",
    );
    await expectLater(
      service.sell(
        items: [const CartItem('v1', 100000)],
        discount: 0,
        received: 0,
        method: 'cash',
        customerName: 'Giới hạn',
      ),
      throwsStateError,
    );
    expect(await service.db.rows('SELECT * FROM documents'), isEmpty);
    expect(
      (await service.db.rows('SELECT quantity FROM stock_balances'))
          .single['quantity'],
      100000,
    );
  });
}
