import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late LocalService service;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = LocalService(db);
    await db.execute(
      "INSERT INTO stores VALUES ('store-cn01','NT-CN01','CN01',1,'2026-11-15')",
    );
    await db.execute(
      "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('device-a2','store-cn01','A2','Máy A2','approved','2026-11-15')",
    );
    await db.execute(
      "INSERT INTO users VALUES ('u1','admin','Chủ','hash','salt',1,0,'2026-11-15')",
    );
    await db.execute(
      "INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES ('p1','Áo','Áo sơ mi','Unisex','Tiểu học','2026–2027','2026-11-15')",
    );
    await db.execute(
      "INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES ('v1','p1','SKU1','M','Trắng','cái',50000,100000,'2026-11-15')",
    );
    service.session = LocalSession(
      userId: 'u1',
      name: 'Chủ',
      role: Role.owner,
      storeId: LocalService.defaultStoreId,
      deviceId: LocalService.defaultDeviceId,
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  });
  tearDown(() async {
    await db.close();
  });

  test('Nhập/xuất qua sổ cái, từ chối âm, audit/outbox nguyên tử', () async {
    await service.adjustStock('v1', 10, 'Nhập đầu kỳ');
    await service.adjustStock('v1', -3, 'Kiểm kê thực tế');
    expect(
      (await db.rows('SELECT quantity FROM stock_balances')).single['quantity'],
      7,
    );
    await expectLater(
      service.adjustStock('v1', -8, 'Xuất quá tồn'),
      throwsStateError,
    );
    expect((await db.rows('SELECT * FROM stock_movements')).length, 2);
    expect((await db.rows('SELECT * FROM audit_logs')).length, 2);
    expect((await db.rows('SELECT * FROM outbox')).length, 4);
    await service.rebuildStockCache();
    expect(
      (await db.rows('SELECT quantity FROM stock_balances')).single['quantity'],
      7,
    );
  });
  test('Sổ cái và audit chặn sửa/xóa bằng trigger', () async {
    await service.adjustStock('v1', 2, 'Nhập');
    await expectLater(
      db.execute('UPDATE stock_movements SET quantity=50'),
      throwsA(anything),
    );
    await expectLater(
      db.execute('DELETE FROM stock_movements'),
      throwsA(anything),
    );
    await expectLater(
      db.execute("UPDATE audit_logs SET action='FAKE'"),
      throwsA(anything),
    );
    await expectLater(db.execute('DELETE FROM audit_logs'), throwsA(anything));
  });
  test('Sai quyền không tạo dữ liệu', () async {
    service.session = LocalSession(
      userId: 'u1',
      name: 'Thu ngân',
      role: Role.cashier,
      storeId: LocalService.defaultStoreId,
      deviceId: LocalService.defaultDeviceId,
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    await expectLater(service.adjustStock('v1', 2, 'Nhập'), throwsStateError);
    expect(await db.rows('SELECT * FROM stock_movements'), isEmpty);
  });
  test('Không lẫn tồn cửa hàng', () async {
    await service.adjustStock('v1', 5, 'Nhập CN01');
    await db.execute(
      "INSERT INTO stores VALUES ('s2','NT-CN02','CN02',1,'2026-11-15')",
    );
    await db.execute(
      "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d2','s2','B1','Máy B1','approved','2026-11-15')",
    );
    await db.execute(
      "INSERT INTO stock_movements VALUES ('m2','s2','d2','v1',12,'receipt',NULL,'Nhập CN02','u1','2026-11-15')",
    );
    final rows = await db.rows(
      'SELECT * FROM stock_balances ORDER BY store_id',
    );
    expect(rows.map((e) => e['quantity']), [12, 5]);
  });
  test('Thiếu lý do bị chặn', () async {
    await expectLater(service.adjustStock('v1', 1, ' '), throwsArgumentError);
  });
}
