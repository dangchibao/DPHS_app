import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Mã và counter dùng ngày phát hành kể cả xử lý qua nửa đêm Việt Nam',
    () async {
      final source = await salesFixture();
      addTearDown(source.db.close);
      final before = DateTime.utc(2026, 11, 15, 16, 59, 59, 999),
          after = DateTime.utc(2026, 11, 15, 17);
      final s = LocalService(source.db, clock: () => after)
        ..session = source.session;
      await s.db.transaction(() async {
        for (final type in ['HD', 'MR', 'DH', 'DT', 'CK']) {
          expect(
            await s.allocateDocumentCode(type, issuedAt: before),
            '$type-CN01-A2-20261115-001',
          );
          expect(
            await s.allocateDocumentCode(type, issuedAt: after),
            '$type-CN01-A2-20261116-001',
          );
        }
      });
      final counters = await s.db.rows(
        'SELECT day,value FROM document_counters',
      );
      expect(counters, hasLength(10));
      expect(counters.every((r) => r['value'] == 1), isTrue);
    },
  );
}
