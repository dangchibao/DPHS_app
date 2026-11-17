import 'dart:convert';

import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';

import 'fixtures.dart';

Future<LocalService> targetFor(LocalService s, String out) async {
  final db = s.db;
  final doc = (await db.rows('SELECT * FROM documents WHERE id=?', [
    out,
  ])).single;
  final lines = await db.rows(
    'SELECT variant_id,quantity,name,size,color,unit,unit_cost,price_version FROM invoice_lines WHERE document_id=?',
    [out],
  );
  await db.execute(
    'INSERT INTO transfer_offers VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
    [
      out,
      's2',
      'd2',
      s.storeId,
      s.deviceId,
      doc['code'],
      'NT-CN01',
      'A2',
      doc['issued_at'],
      s.now,
      doc['school_year'],
      jsonEncode(lines),
      'Chuyển CN02',
    ],
  );
  return LocalService(db, storeId: 's2', deviceId: 'd2', clock: s.clock)
    ..session = LocalSession(
      userId: 'u1',
      name: 'Kho CN02',
      role: Role.warehouse,
      storeId: 's2',
      deviceId: 'd2',
      expiresAt: DateTime.utc(2027),
    );
}

Future<LocalService> fixture() async {
  final s = await salesFixture();
  await s.db.execute(
    "INSERT INTO stores VALUES('s2','NT-CN02','CN02',1,'2026-11-15')",
  );
  await s.db.execute(
    "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d2','s2','B3','Máy nhận','approved','2026-11-15')",
  );
  await s.db.execute('INSERT INTO local_settings VALUES (?,?)', [
    'transfer_targets',
    jsonEncode([
      {
        'store_id': 's2',
        'store_code': 'NT-CN02',
        'store_name': 'CN02',
        'device_id': 'd2',
        'device_code': 'B3',
        'device_name': 'Máy nhận',
      },
    ]),
  ]);
  return s;
}
