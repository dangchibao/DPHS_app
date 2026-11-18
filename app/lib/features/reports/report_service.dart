import 'dart:convert';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../../core/money.dart';

class ReportRange {
  ReportRange(this.fromDay, this.toDay, {String? schoolId, String? year})
    : schoolId = schoolId?.trim(),
      year = year?.trim() {
    DateTime parse(String value) {
      final d = DateTime.tryParse('${value}T00:00:00.000Z');
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          d == null ||
          d.toIso8601String().substring(0, 10) != value ||
          d.year < 2000) {
        throw ArgumentError('Ngày báo cáo dạng YYYY-MM-DD, từ năm 2000.');
      }
      return d;
    }

    final start = parse(fromDay), end = parse(toDay);
    if (end.isBefore(start) || end.difference(start).inDays > 365) {
      throw ArgumentError('Chọn khoảng từ 1 đến 366 ngày.');
    }
    from = start.subtract(const Duration(hours: 7)).toIso8601String();
    to = end
        .add(const Duration(days: 1))
        .subtract(const Duration(hours: 7))
        .toIso8601String();
    if ((this.year?.length ?? 0) > 30) {
      throw ArgumentError('Năm học không hợp lệ.');
    }
  }
  final String fromDay, toDay;
  final String? schoolId, year;
  late final String from, to;
}

class ReportTable {
  const ReportTable(this.headers, this.rows, {this.moneyColumns = const {}});
  final List<String> headers;
  final List<List<Object?>> rows;
  final Set<int> moneyColumns;
  List<List<Object?>> pdfRows() => [
    for (final row in rows)
      [
        for (var c = 0; c < row.length; c++)
          if (row[c] is BigInt)
            moneyColumns.contains(c)
                ? formatWholeVnd(row[c] as BigInt)
                : (row[c] as BigInt).toString()
          else
            row[c],
      ],
  ];
  List<List<Object?>> excelRows() => [
    for (final row in rows)
      [
        for (final value in row)
          if (value is BigInt)
            value.abs().toString().length <= 15
                ? value.toInt()
                : value.toString()
          else
            value,
      ],
  ];
}

class ReportData {
  ReportData(
    this.range,
    this.totals,
    this.tables,
    this.generatedAt, {
    this.storeLabel = '',
  });
  final ReportRange range;
  final Map<String, BigInt> totals;
  final Map<String, ReportTable> tables;
  final String generatedAt;
  final String storeLabel;
}

class _Bucket {
  _Bucket(this.name);
  String name;
  BigInt quantity = BigInt.zero,
      revenue = BigInt.zero,
      cost = BigInt.zero,
      incoming = BigInt.zero,
      refund = BigInt.zero;
  void add(BigInt q, BigInt r, BigInt c) {
    quantity += q;
    revenue += r;
    cost += c;
  }
}

extension ReportService on LocalService {
  Future<List<Map<String, Object?>>> reportSchools() {
    require(Permission.reports);
    return db.rows(
      'SELECT id,name FROM schools WHERE store_id=? ORDER BY name',
      [storeId],
    );
  }

  Future<ReportData> localReport(
    ReportRange range, {
    bool Function()? isCancelled,
  }) async {
    final actor = require(Permission.reports);
    return db.transaction(() async {
      if (require(Permission.reports).userId != actor.userId) {
        throw StateError('Phiên đã thay đổi.');
      }
      final nowSnapshot = now;
      final identity = (await db.rows(
        'SELECT name,code FROM stores WHERE id=?',
        [storeId],
      )).single;
      final scope =
          "d.store_id=? AND d.issued_at>=? AND d.issued_at<? ${range.year?.isNotEmpty == true ? 'AND d.school_year=?' : ''} ${range.schoolId?.isNotEmpty == true ? "AND json_extract(d.metadata_json,'\$.school_id')=?" : ''}";
      final args = <Object?>[
        storeId,
        range.from,
        range.to,
        if (range.year?.isNotEmpty == true) range.year,
        if (range.schoolId?.isNotEmpty == true) range.schoolId,
      ];
      final headers = await db.rows(
        "SELECT d.* FROM documents d WHERE $scope AND d.type='MR' ORDER BY d.issued_at",
        args,
      );
      final counts = (await db.rows(
        "SELECT COALESCE(SUM(CASE WHEN d.type IN ('HD','MR') THEN 1 ELSE 0 END),0) AS invoices,COALESCE(SUM(CASE WHEN d.type='DT' THEN 1 ELSE 0 END),0) AS returns FROM documents d WHERE $scope",
        args,
      )).single;
      Future<void> scan(
        String sql,
        String timeKey,
        String idKey,
        List<Object?> arguments,
        void Function(Map<String, Object?>) consume,
      ) async {
        var lastTime = range.from, lastId = '';
        while (true) {
          if (isCancelled?.call() == true) {
            throw StateError('Đã đóng báo cáo.');
          }
          require(Permission.reports);
          final page = await db.rows(
            '$sql AND ($timeKey>? OR ($timeKey=? AND $idKey>?)) ORDER BY $timeKey,$idKey LIMIT 1000',
            [...arguments, lastTime, lastTime, lastId],
          );
          for (final row in page) {
            consume(row);
          }
          if (page.length < 1000) {
            break;
          }
          lastTime = page.last['cursor_time'] as String;
          lastId = page.last['cursor_id'] as String;
        }
      }

      final users = {
        for (final row in await db.rows(
          'SELECT u.id,u.display_name FROM users u JOIN employee_store_assignments a ON a.user_id=u.id WHERE a.store_id=?',
          [storeId],
        ))
          row['id'] as String: row['display_name'] as String,
      };
      final days = <String, _Bucket>{},
          products = <String, _Bucket>{},
          sizes = <String, _Bucket>{},
          employees = <String, _Bucket>{};
      final total = _Bucket('Tổng');
      void add(
        Map<String, Object?> row,
        BigInt quantity,
        BigInt revenue,
        BigInt cost,
      ) {
        final day = DateTime.parse(row['issued_at'] as String)
                .toUtc()
                .add(const Duration(hours: 7))
                .toIso8601String()
                .substring(0, 10),
            employee = row['user_id'] as String;
        for (final b in [
          total,
          days.putIfAbsent(day, () => _Bucket(day)),
          products.putIfAbsent(
            row['product_id'] as String,
            () => _Bucket(row['name'] as String),
          ),
          sizes.putIfAbsent(
            row['size'] as String,
            () => _Bucket(row['size'] as String),
          ),
          employees.putIfAbsent(
            employee,
            () => _Bucket(users[employee] ?? employee),
          ),
        ]) {
          b.add(quantity, revenue, cost);
        }
      }

      await scan(
        'SELECT d.issued_at,d.issued_at AS cursor_time,l.id AS cursor_id,d.user_id,l.*,v.product_id FROM documents d JOIN invoice_lines l ON l.store_id=d.store_id AND l.document_id=d.id JOIN product_variants v ON v.id=l.variant_id WHERE $scope AND d.type IN (\'HD\',\'MR\',\'DT\')',
        'd.issued_at',
        'l.id',
        args,
        (l) {
          final q = BigInt.from(l['quantity'] as int);
          add(
            l,
            q,
            q * BigInt.from(l['unit_price'] as int) -
                BigInt.from(l['discount'] as int),
            q * BigInt.from(l['unit_cost'] as int),
          );
        },
      );
      await scan(
        'SELECT d.issued_at,d.issued_at AS cursor_time,r.id AS cursor_id,o.user_id,r.quantity,r.credit,l.name,l.size,l.unit_cost,v.product_id FROM documents d JOIN return_lines r ON r.store_id=d.store_id AND r.document_id=d.id JOIN invoice_lines l ON l.store_id=r.store_id AND l.id=r.original_line_id JOIN documents o ON o.store_id=l.store_id AND o.id=l.document_id JOIN product_variants v ON v.id=l.variant_id WHERE $scope',
        'd.issued_at',
        'r.id',
        args,
        (r) {
          final q = BigInt.from(r['quantity'] as int);
          add(
            r,
            -q,
            -BigInt.from(r['credit'] as int),
            -q * BigInt.from(r['unit_cost'] as int),
          );
        },
      );
      final financialFilter =
          "d.store_id=? ${range.year?.isNotEmpty == true ? 'AND d.school_year=?' : ''} ${range.schoolId?.isNotEmpty == true ? "AND json_extract(d.metadata_json,'\$.school_id')=?" : ''}";
      final financialArgs = <Object?>[
        storeId,
        if (range.year?.isNotEmpty == true) range.year,
        if (range.schoolId?.isNotEmpty == true) range.schoolId,
      ];
      await scan(
        'SELECT p.amount,p.direction,p.created_at,p.created_at AS cursor_time,p.id AS cursor_id FROM payments p INDEXED BY payments_store_created JOIN documents d ON d.store_id=p.store_id AND d.id=p.document_id WHERE $financialFilter AND p.created_at>=? AND p.created_at<?',
        'p.created_at',
        'p.id',
        [...financialArgs, range.from, range.to],
        (p) {
          final day = DateTime.parse(p['created_at'] as String)
                  .toUtc()
                  .add(const Duration(hours: 7))
                  .toIso8601String()
                  .substring(0, 10),
              b = days.putIfAbsent(day, () => _Bucket(day)),
              amount = BigInt.from(p['amount'] as int);
          if (p['direction'] == 'receive') {
            total.incoming += amount;
            b.incoming += amount;
          } else {
            total.refund += amount;
            b.refund += amount;
          }
        },
      );
      final ledger = await db.rows(
        "SELECT r.document_id,CAST(SUM(r.amount) AS TEXT) AS amount,COALESCE(MIN(NULLIF(r.due_date,'')),'') AS due_date,d.code,COALESCE(json_extract(d.metadata_json,'\$.customer_name'),c.name,'Khách') AS customer_name FROM receivable_ledger r JOIN documents d ON d.store_id=r.store_id AND d.id=r.document_id LEFT JOIN customers c ON c.store_id=d.store_id AND c.id=d.customer_id WHERE $financialFilter AND r.created_at<? GROUP BY r.document_id HAVING SUM(r.amount)>0",
        [...financialArgs, range.to],
      );
      final balances =
          <
            String,
            ({String code, String customer, String due, BigInt amount})
          >{};
      for (final r in ledger) {
        final id = r['document_id'] as String,
            old = balances[id],
            due = r['due_date'] as String;
        balances[id] = (
          code: r['code'] as String,
          customer: r['customer_name'] as String,
          due: old == null || old.due.isEmpty
              ? due
              : due.isNotEmpty && due.compareTo(old.due) < 0
              ? due
              : old.due,
          amount:
              (old?.amount ?? BigInt.zero) +
              BigInt.parse(r['amount'] as String),
        );
      }
      var debt = BigInt.zero, overdue = BigInt.zero;
      final debtRows = <List<Object?>>[];
      for (final b in balances.values) {
        if (b.amount <= BigInt.zero) {
          continue;
        }
        final late = b.due.isNotEmpty && b.due.compareTo(range.toDay) < 0;
        debt += b.amount;
        if (late) {
          overdue += b.amount;
        }
        debtRows.add([
          b.code,
          b.customer,
          b.amount,
          b.due,
          late ? 'Quá hạn' : 'Chưa quá hạn',
        ]);
      }
      debtRows.sort((a, b) => (b[2] as BigInt).compareTo(a[2] as BigInt));
      final inventory = await db.rows(
        "SELECT v.*,p.name,COALESCE(b.quantity,0) AS stock,COALESCE((SELECT SUM(r.quantity) FROM reservation_lines r WHERE r.store_id=? AND r.variant_id=v.id AND r.created_at<=? AND r.expires_at>? AND NOT EXISTS(SELECT 1 FROM reservation_events e WHERE e.store_id=r.store_id AND e.document_id=r.document_id AND e.created_at<=?)),0) AS reserved FROM product_variants v JOIN products p ON p.id=v.product_id LEFT JOIN stock_balances b ON b.store_id=? AND b.variant_id=v.id ${range.year?.isNotEmpty == true ? 'WHERE p.school_year=?' : ''} ORDER BY stock DESC,p.name,v.size",
        [
          storeId,
          nowSnapshot,
          nowSnapshot,
          nowSnapshot,
          storeId,
          if (range.year?.isNotEmpty == true) range.year,
        ],
      );
      final stockRows = <List<Object?>>[
        for (final r in inventory)
          [
            r['name'],
            r['size'],
            r['color'],
            r['stock'],
            r['reserved'],
            (r['stock'] as int) - (r['reserved'] as int),
            BigInt.from(r['cost'] as int) * BigInt.from(r['stock'] as int),
          ],
      ];
      final events = await db.rows(
        "SELECT e.document_id,e.type FROM document_events e JOIN documents d ON d.store_id=e.store_id AND d.id=e.document_id WHERE $scope AND d.type='MR' AND e.created_at<?",
        [...args, range.to],
      );
      final stages = <String, int>{};
      for (final e in events) {
        final rank =
                {
                  'TAILOR_SEWING': 1,
                  'TAILOR_READY': 2,
                  'TAILOR_DELIVERED': 3,
                }[e['type']] ??
                0,
            id = e['document_id'] as String;
        if (rank > (stages[id] ?? 0)) {
          stages[id] = rank;
        }
      }
      final tailorRows = <List<Object?>>[];
      for (final h in headers.where((h) => h['type'] == 'MR')) {
        final m = jsonDecode(h['metadata_json'] as String) as Map;
        final data = m['tailoring'] as Map? ?? {};
        tailorRows.add([
          h['code'],
          m['customer_name'] ?? '',
          data['due_date'] ?? '',
          ['Mới nhận', 'Đang may', 'Xong', 'Đã giao'][stages[h['id']] ?? 0],
          BigInt.from(h['total'] as int),
        ]);
      }
      List<List<Object?>> ranking(Map<String, _Bucket> buckets) {
        final rows = buckets.values.toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));
        return [
          for (final b in rows)
            [b.name, b.quantity, b.revenue, b.cost, b.revenue - b.cost],
        ];
      }

      final sortedDays = days.keys.toList()..sort();
      final totals = <String, BigInt>{
        'revenue': total.revenue,
        'cost': total.cost,
        'gross_profit': total.revenue - total.cost,
        'quantity': total.quantity,
        'payment_in': total.incoming,
        'payment_out': total.refund,
        'cashflow': total.incoming - total.refund,
        'debt': debt,
        'overdue': overdue,
        'invoices': BigInt.from(counts['invoices'] as int),
        'returns': BigInt.from(counts['returns'] as int),
        'tailoring': BigInt.from(tailorRows.length),
      };
      final tables = <String, ReportTable>{
        'Doanh thu theo ngày': ReportTable(
          [
            'Ngày',
            'Doanh thu thuần',
            'Giá vốn',
            'Lãi gộp',
            'Thu tiền',
            'Hoàn tiền',
          ],
          [
            for (final day in sortedDays)
              [
                day,
                days[day]!.revenue,
                days[day]!.cost,
                days[day]!.revenue - days[day]!.cost,
                days[day]!.incoming,
                days[day]!.refund,
              ],
          ],
          moneyColumns: {1, 2, 3, 4, 5},
        ),
        'Sản phẩm · lãi gộp': ReportTable(
          ['Sản phẩm', 'SL thuần', 'Doanh thu', 'Giá vốn', 'Lãi gộp'],
          ranking(products),
          moneyColumns: {2, 3, 4},
        ),
        'Size bán chạy': ReportTable(
          ['Size', 'SL thuần', 'Doanh thu', 'Giá vốn', 'Lãi gộp'],
          ranking(sizes)
            ..sort((a, b) => (b[1] as BigInt).compareTo(a[1] as BigInt)),
          moneyColumns: {2, 3, 4},
        ),
        'Tồn kho hiện tại': ReportTable(
          [
            'Sản phẩm',
            'Size',
            'Màu',
            'Tồn thực',
            'Đang giữ',
            'Khả dụng',
            'Giá vốn hiện tại',
          ],
          stockRows,
          moneyColumns: {6},
        ),
        'Đơn may riêng': ReportTable(
          ['Mã', 'Khách', 'Hẹn trả', 'Trạng thái cuối kỳ', 'Giá trị đơn'],
          tailorRows,
          moneyColumns: {4},
        ),
        'Công nợ cuối kỳ': ReportTable(
          ['Chứng từ', 'Khách', 'Còn nợ', 'Hạn trả', 'Trạng thái'],
          debtRows,
          moneyColumns: {2},
        ),
        'Hiệu suất nhân viên': ReportTable(
          ['Nhân viên', 'SL thuần', 'Doanh thu', 'Giá vốn', 'Lãi gộp'],
          ranking(employees),
          moneyColumns: {2, 3, 4},
        ),
      };
      if (require(Permission.reports).userId != actor.userId) {
        throw StateError('Phiên đã thay đổi.');
      }
      return ReportData(
        range,
        totals,
        tables,
        nowSnapshot,
        storeLabel: '${identity['code']} · ${identity['name']}',
      );
    });
  }
}
