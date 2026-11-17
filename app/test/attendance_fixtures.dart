import 'package:ngoc_thanh_pos/core/local_service.dart';

import 'fixtures.dart';

Future<LocalService> attendanceFixture() async {
  final original = await salesFixture();
  var tick = 0;
  final s = LocalService(
    original.db,
    clock: () => DateTime.utc(2026, 11, 15).add(Duration(milliseconds: tick++)),
  )..session = original.session;
  await s.db.execute(
    'INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?)',
    ['assignment', s.storeId, 'u1', 'owner', 1, s.now],
  );
  return s;
}
