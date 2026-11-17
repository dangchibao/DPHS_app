import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';

extension DebtService on LocalService {
  Future<List<Map<String, Object?>>> debts({bool overdueOnly = false}) {
    require(Permission.collect);
    final today = clock()
        .toUtc()
        .add(const Duration(hours: 7))
        .toIso8601String()
        .substring(0, 10);
    return db.rows(
      '''SELECT d.id,d.code,d.total,d.device_id,c.name,c.phone,c.kind,
      SUM(r.amount) AS balance,MIN(CASE WHEN r.amount>0 THEN r.due_date END) AS due_date
      FROM receivable_ledger r JOIN documents d ON d.id=r.document_id AND d.store_id=r.store_id
      JOIN customers c ON c.id=r.customer_id AND c.store_id=r.store_id
      WHERE r.store_id=? GROUP BY d.id HAVING balance>0 ${overdueOnly ? 'AND due_date<?' : ''}
      ORDER BY due_date,d.code''',
      [storeId, if (overdueOnly) today],
    );
  }

  Future<List<Map<String, Object?>>> paymentHistory(String documentId) {
    require(Permission.collect);
    return db.rows(
      'SELECT p.*,u.display_name FROM payments p JOIN users u ON u.id=p.user_id WHERE p.store_id=? AND p.document_id=? ORDER BY p.created_at,p.id',
      [storeId, documentId],
    );
  }

  Future<List<Map<String, Object?>>> debtCredits(String documentId) {
    require(Permission.collect);
    return db.rows(
      'SELECT a.*,d.code FROM receivable_adjustments a JOIN documents d ON d.store_id=a.store_id AND d.id=a.credit_document_id WHERE a.store_id=? AND a.document_id=? ORDER BY a.created_at,a.id',
      [storeId, documentId],
    );
  }

  Future<String> collectDebt({
    required String documentId,
    required int amount,
    required String method,
    required String note,
    String? commandId,
  }) async {
    final actor = require(Permission.collect);
    if (amount <= 0 ||
        amount > 9007199254740991 ||
        !['cash', 'bank'].contains(method) ||
        note.trim().isEmpty) {
      throw ArgumentError(
        'Nhập số tiền nguyên dương, phương thức và nội dung thu.',
      );
    }
    final id = commandId ?? uuid.v7();
    return db.transaction(() async {
      final previous = await db.rows('SELECT * FROM payments WHERE id=?', [id]);
      if (previous.isNotEmpty) {
        final p = previous.single;
        if (p['store_id'] != storeId ||
            p['device_id'] != deviceId ||
            p['user_id'] != actor.userId ||
            p['document_id'] != documentId ||
            p['amount'] != amount ||
            p['method'] != method ||
            p['note'] != note.trim() ||
            p['direction'] != 'receive') {
          throw StateError('Mã thu tiền đã dùng với nội dung khác.');
        }
        return id;
      }
      final docs = await db.rows(
        "SELECT * FROM documents WHERE store_id=? AND id=? AND ((type='HD' AND kind='sale') OR (type='MR' AND kind='tailoring') OR (type='DT' AND kind IN ('return','exchange')))",
        [storeId, documentId],
      );
      if (docs.isEmpty || docs.single['device_id'] != deviceId) {
        throw StateError('Thu nợ offline cần dùng thiết bị đã lập hóa đơn.');
      }
      final customer = docs.single['customer_id'];
      final balance =
          (await db.rows(
                'SELECT COALESCE(SUM(amount),0) AS balance FROM receivable_ledger WHERE store_id=? AND document_id=?',
                [storeId, documentId],
              )).single['balance']
              as int;
      if (customer == null || amount > balance) {
        throw StateError('Số tiền thu vượt công nợ còn lại.');
      }
      final time = now;
      await db.execute('INSERT INTO payments VALUES (?,?,?,?,?,?,?,?,?,?)', [
        id,
        storeId,
        deviceId,
        documentId,
        actor.userId,
        amount,
        method,
        'receive',
        time,
        note.trim(),
      ]);
      await db.execute(
        'INSERT INTO receivable_entries VALUES (?,?,?,?,?,?,?,?)',
        [uuid.v7(), storeId, customer, documentId, id, -amount, '', time],
      );
      await audit(
        'PAYMENT_RECEIVE',
        'document',
        documentId,
        reason: note.trim(),
        severity: 'sensitive',
        changes: {
          'payment_id': id,
          'amount': amount,
          'method': method,
          'balance_before': balance,
          'balance_after': balance - amount,
        },
      );
      await enqueue('payment', {'id': id}, 0);
      return id;
    });
  }
}
