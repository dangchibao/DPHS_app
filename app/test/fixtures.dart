import 'package:drift/native.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';

Future<LocalService> salesFixture({AppDatabase? database}) async {
  final db = database ?? AppDatabase(NativeDatabase.memory());
  final service = LocalService(db, clock: () => DateTime.utc(2026, 11, 15));
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
    "INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES ('p1','Áo sơ mi','Áo sơ mi','Unisex','Tiểu học','2026–2027','2026-11-15')",
  );
  await db.execute(
    "INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES ('v1','p1','SKU1','M','Trắng','cái',50000,100000,'2026-11-15')",
  );
  service.session = LocalSession(
    userId: 'u1',
    name: 'Chủ',
    role: Role.owner,
    storeId: service.storeId,
    deviceId: service.deviceId,
    expiresAt: DateTime.utc(2027),
  );
  await service.adjustStock('v1', 10, 'Tồn đầu');
  return service;
}
