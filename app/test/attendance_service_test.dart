import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/employees/attendance_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';

import 'attendance_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Ngày công đối chiếu đúng timestamp sự kiện khi qua nửa đêm Việt Nam',
    () async {
      final original = await attendanceFixture();
      addTearDown(original.db.close);
      for (var offset = 0; offset <= 8; offset++) {
        var ticks = 0;
        final boundary = DateTime.utc(2026, 11, 15, 17);
        final s = LocalService(
          original.db,
          clock: () => boundary.add(Duration(milliseconds: ticks++ - offset)),
        )..session = original.session;
        try {
          final id = await s.markAttendance(
            employeeId: 'u1',
            day: '2026-11-16',
            units: 1,
            reason: 'Qua nửa đêm',
          );
          final entry = (await s.db.rows(
            'SELECT * FROM attendance_entries WHERE id=?',
            [id],
          )).single;
          final createdDay = DateTime.parse(entry['created_at'] as String)
              .add(const Duration(hours: 7))
              .toIso8601String()
              .substring(0, 10);
          expect(
            (entry['work_day'] as String).compareTo(createdDay) <= 0,
            isTrue,
          );
        } on ArgumentError {
          // Từ chối hợp lệ nếu timestamp sự kiện còn thuộc ngày trước.
        }
      }
    },
  );
  test(
    'Công nửa ngày/ngày cập nhật bằng event, audit/outbox cùng transaction',
    () async {
      final s = await attendanceFixture();
      addTearDown(s.db.close);
      await s.markAttendance(
        employeeId: 'u1',
        day: '2026-11-15',
        units: 1,
        reason: 'Nửa ngày',
      );
      await s.markAttendance(
        employeeId: 'u1',
        day: '2026-11-15',
        units: 2,
        reason: 'Đối soát đủ ngày',
      );
      final rows = await s.attendance(from: '2026-11-01', to: '2026-12-01');
      expect(rows, hasLength(1));
      expect(rows.single['day_units'], 2);
      expect(rows.single['pending'], isTrue);
      expect(await s.db.rows('SELECT * FROM attendance_entries'), hasLength(2));
      expect(
        await s.db.rows("SELECT * FROM outbox WHERE entity_type='attendance'"),
        hasLength(2),
      );
      expect(daysText(3), '1,5');
    },
  );
  test(
    'Kỳ khóa chặn sửa; event bị server reject không ghi đè ngày công trước',
    () async {
      final s = await attendanceFixture();
      addTearDown(s.db.close);
      await s.markAttendance(
        employeeId: 'u1',
        day: '2026-11-15',
        units: 2,
        reason: 'Đủ ngày',
      );
      final late = await s.markAttendance(
        employeeId: 'u1',
        day: '2026-11-15',
        units: 0,
        reason: 'Sửa offline',
      );
      await s.db.execute('INSERT INTO payroll_locks VALUES(?,?,?,?,?,?,?)', [
        'lock',
        s.storeId,
        'u1',
        'run',
        '2026-11-01',
        '2026-12-01',
        s.now,
      ]);
      await s.db.execute(
        'INSERT INTO attendance_rejections VALUES(?,?,?,?,?,?,?,?,?)',
        [
          late,
          s.storeId,
          s.deviceId,
          'u1',
          'u1',
          '2026-11-15',
          'fixture-hash',
          'Kỳ đã khóa',
          s.now,
        ],
      );
      expect(
        (await s.attendance(
          from: '2026-11-01',
          to: '2026-12-01',
        )).single['day_units'],
        2,
      );
      await expectLater(
        s.markAttendance(
          employeeId: 'u1',
          day: '2026-11-15',
          units: 1,
          reason: 'Sửa',
        ),
        throwsStateError,
      );
      expect(
        await s.attendanceRejections(from: '2026-11-01', to: '2026-12-01'),
        hasLength(1),
      );
    },
  );
  test('Chặn ngày tương lai/sai và thu ngân không chấm công', () async {
    final s = await attendanceFixture();
    addTearDown(s.db.close);
    await expectLater(
      s.markAttendance(
        employeeId: 'u1',
        day: '2026-11-16',
        units: 2,
        reason: 'Tương lai',
      ),
      throwsArgumentError,
    );
    await expectLater(
      s.markAttendance(
        employeeId: 'u1',
        day: '2026-02-30',
        units: 2,
        reason: 'Sai ngày',
      ),
      throwsArgumentError,
    );
    s.session = LocalSession(
      userId: 'u1',
      name: 'Thu ngân',
      role: Role.cashier,
      storeId: s.storeId,
      deviceId: s.deviceId,
      expiresAt: DateTime.utc(2027),
    );
    await expectLater(
      s.markAttendance(
        employeeId: 'u1',
        day: '2026-11-15',
        units: 2,
        reason: 'Tự chấm',
      ),
      throwsStateError,
    );
  });
}
