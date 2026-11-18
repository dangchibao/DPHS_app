import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Ghi audit nối mốc cloud đã lưu trữ, không reset số; mốc cũ không làm lùi chain', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    final hash = 'a' * 64;
    await s.db.transaction(
      () => s.acceptAuditHead({'chain_index': 50, 'hash': hash}),
    );
    await s.db.transaction(() => s.audit('PRODUCT_UPDATE', 'variant', 'v1'));
    final row = (await s.db.rows(
      'SELECT chain_index,hash_prev FROM audit_logs ORDER BY chain_index DESC LIMIT 1',
    )).single;
    expect(row['chain_index'], 51);
    expect(row['hash_prev'], hash);
    await s.db.transaction(
      () => s.acceptAuditHead({'chain_index': 20, 'hash': 'b' * 64}),
    );
    await s.db.transaction(() => s.audit('PRODUCT_UPDATE', 'variant', 'v1'));
    expect(
      (await s.db.rows('SELECT MAX(chain_index) n FROM audit_logs'))
          .single['n'],
      52,
    );
    await expectLater(
      s.acceptAuditHead({'chain_index': 52, 'hash': 'f' * 64}),
      throwsStateError,
    );
    await expectLater(
      s.acceptAuditHead({'chain_index': -1, 'hash': ''}),
      throwsStateError,
    );
  });
}
