import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:ngoc_thanh_pos/core/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Nâng bản preview schema 9 giữ hóa đơn, công nợ, kho và hàng đợi',
    () async {
      final directory = await Directory.systemTemp.createTemp('nt-v9-upgrade-');
      final file = File('${directory.path}/migration.sqlite');
      final native = sqlite.sqlite3.open(file.path);
      for (final name in [
        '0001_foundation',
        '0002_local_core',
        '0003_auth_and_settings',
        '0004_sync',
        '0005_sales',
        '0006_operations',
        '0007_sync_capabilities',
        '0008_price_history',
        '0009_collections',
      ]) {
        native.execute(
          await rootBundle.loadString('assets/migrations/$name.sql'),
        );
      }
      native.execute('''
INSERT INTO stores VALUES ('s1','NT-CN01','Chi nhánh',1,'2026-11-15');
INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d1','s1','A2','Máy','approved','2026-11-15');
INSERT INTO users VALUES ('u1','admin','Chủ','hash','salt',1,0,'2026-11-15');
INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES ('p1','Áo','Áo sơ mi','Unisex','Tiểu học','2026–2027','2026-11-15');
INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at) VALUES ('v1','p1','SKU1','M','Trắng','cái',50000,100000,'2026-11-15');
INSERT INTO customers(id,store_id,name,updated_at) VALUES ('c1','s1','Phụ huynh','2026-11-15');
INSERT INTO documents VALUES ('hd1','s1','d1','HD','sale','HD-CN01-A2-20261115-001','2026-11-15','u1','c1',NULL,100000,0,100000,'2026–2027','{}');
INSERT INTO invoice_lines VALUES ('line1','s1','hd1','v1','Áo lúc bán','M','Trắng','cái',1,100000,50000,0,'');
INSERT INTO payments VALUES ('pay1','s1','d1','hd1','u1',25000,'cash','receive','2026-11-15','Đặt cọc');
INSERT INTO receivable_entries VALUES ('debt1','s1','c1','hd1',NULL,75000,'2026-11-30','2026-11-15');
INSERT INTO stock_movements VALUES ('in1','s1','d1','v1',5,'receipt',NULL,'Tồn đầu','u1','2026-11-15');
INSERT INTO stock_movements VALUES ('out1','s1','d1','v1',-1,'sale','hd1','Bán hàng','u1','2026-11-15');
INSERT INTO document_counters VALUES ('s1','d1','HD','20261115',1);
INSERT INTO outbox(id,store_id,device_id,entity_type,payload,priority,created_at,actor_id) VALUES ('job1','s1','d1','sale','[]',0,'2026-11-15','u1');
INSERT INTO sync_cursors VALUES ('store-cn01',123);
PRAGMA user_version=9;
''');
      native.close();
      final db = AppDatabase(NativeDatabase(file));
      try {
        expect((await db.rows('SELECT code,total FROM documents')).single, {
          'code': 'HD-CN01-A2-20261115-001',
          'total': 100000,
        });
        expect(
          (await db.rows('SELECT name FROM invoice_lines')).single['name'],
          'Áo lúc bán',
        );
        expect(
          (await db.rows('SELECT amount FROM receivable_entries'))
              .single['amount'],
          75000,
        );
        expect(
          (await db.rows('SELECT quantity FROM stock_balances'))
              .single['quantity'],
          4,
        );
        expect(
          (await db.rows('SELECT quantity FROM device_stock_allocations'))
              .single['quantity'],
          4,
        );
        expect(
          (await db.rows('SELECT actor_id FROM outbox')).single['actor_id'],
          'u1',
        );
        expect(
          (await db.rows('SELECT value FROM document_counters'))
              .single['value'],
          1,
        );
        expect(await db.rows('PRAGMA foreign_key_check'), isEmpty);
        expect(await db.rows('SELECT * FROM sync_cursors'), isEmpty);
        expect(await db.rows('SELECT * FROM combo_rules'), isEmpty);
        expect(await db.rows('SELECT * FROM local_audit_receipts'), isEmpty);
        await expectLater(
          db.execute("UPDATE documents SET total=0 WHERE id='hd1'"),
          throwsA(isA<Exception>()),
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test('Tách SQL giữ dấu chấm phẩy trong comment và chuỗi', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.applySql('''
-- ghi chú; không phải statement
CREATE TABLE parser_test ("name;field" TEXT);
/* comment; nhiều dòng */
INSERT INTO parser_test VALUES ('áo; học sinh''s');
-- comment cuối; không có câu lệnh
''');
      expect(
        (await db.rows('SELECT * FROM parser_test')).single.values.single,
        "áo; học sinh's",
      );
      expect(splitSchemaStatements('-- chỉ comment;').toList(), isEmpty);
    } finally {
      await db.close();
    }
  });
  test('Nâng schema v1 lên hiện hành giữ nguyên cửa hàng', () async {
    final directory = await Directory.systemTemp.createTemp('nt-migration-');
    final file = File('${directory.path}/migration.sqlite');
    final native = sqlite.sqlite3.open(file.path);
    native.execute(
      await rootBundle.loadString('assets/migrations/0001_foundation.sql'),
    );
    native.execute(
      "INSERT INTO stores VALUES ('s1','NT-CN01','Cửa hàng gốc',1,'2026-11-15'); PRAGMA user_version=1;",
    );
    native.close();
    final db = AppDatabase(NativeDatabase(file));
    try {
      expect(
        (await db.rows('SELECT name FROM stores')).single['name'],
        'Cửa hàng gốc',
      );
      expect(
        (await db.rows('PRAGMA user_version')).single.values.single,
        db.schemaVersion,
      );
      expect(await db.rows('SELECT * FROM audit_logs'), isEmpty);
      expect(await db.rows('SELECT * FROM size_chart_rules'), isEmpty);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
