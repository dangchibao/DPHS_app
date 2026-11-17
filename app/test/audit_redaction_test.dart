import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/core/auth/audit_redaction.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final vectors = jsonDecode(
    File('../docs/test-vectors/audit-redaction.json').readAsStringSync(),
  ) as List;
  for (final v in vectors) {
    test(
      v['name'] as String,
      () => expect(
        redactAuditChanges(
          Map<String, Object?>.from(v['changes'] as Map),
          action: v['action'] as String,
        ),
        v['expected'],
      ),
    );
  }
  test(
    'Audit lưu và outbox đều che trước hash, nhật ký vẫn append-only',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      await s.db.transaction(
        () => s.audit(
          'PAYROLL_RULE_SAVE',
          'employee',
          'u1',
          changes: {
            'employee_id': 'u1',
            'amount': 10000000,
            'config': {'base_salary': 10000000},
          },
        ),
      );
      final row = (await s.db.rows(
        "SELECT * FROM audit_logs WHERE action='PAYROLL_RULE_SAVE'",
      )).single;
      expect(row['changes_json'], isNot(contains('10000000')));
      expect(jsonDecode(row['changes_json'] as String)['amount'], auditMask);
      final payloads = await s.db.rows(
        "SELECT payload FROM outbox WHERE entity_type='audit'",
      );
      expect(
        payloads.any((r) => (r['payload'] as String).contains('10000000')),
        isFalse,
      );
      await expectLater(
        s.db.execute("UPDATE audit_logs SET changes_json='{}' WHERE id=?", [
          row['id'],
        ]),
        throwsA(anything),
      );
    },
  );
}
