import 'dart:convert';

import '../../core/sync/cloud_api.dart';
import 'report_service.dart';

class CloudReportRows {
  CloudReportRows(this.rows, this.generatedAt);
  final List<Map<String, Object?>> rows;
  final String? generatedAt;
}

class CloudReports {
  CloudReports(this.api);
  final CloudApi api;
  Future<Map<String, Object?>> options() => api.send('/reports/options');
  Future<Map<String, Object?>> rebuild(String store) =>
      api.send('/reports/rebuild', body: {'store_id': store});
  String path(
    String route,
    ReportRange range,
    String store, {
    String? kind,
    String? cursor,
    String? since,
  }) =>
      '$route?${Uri(queryParameters: {'from': range.fromDay, 'to': range.toDay, 'store': store, if (range.year?.isNotEmpty == true) 'year': range.year!, if (range.schoolId?.isNotEmpty == true) 'school': range.schoolId!, 'kind': ?kind, 'cursor': ?cursor, 'since': ?since}).query}';
  Future<CloudReportRows> pages(
    String route,
    ReportRange range,
    String store, {
    String? kind,
    Map<String, Object?>? first,
    bool Function()? isCancelled,
  }) async {
    final rows = <Map<String, Object?>>[], seen = <String>{};
    String? next, time;
    for (var page = 0; page < 10000; page++) {
      if (isCancelled?.call() == true) {
        throw StateError('Đã đóng báo cáo.');
      }
      final result = page == 0 && first != null
          ? first
          : await api.send(path(route, range, store, kind: kind, cursor: next));
      if (result['rows'] is! List) {
        throw StateError('Cloud trả dữ liệu báo cáo không hợp lệ.');
      }
      for (final row in result['rows'] as List) {
        rows.add(Map<String, Object?>.from(row as Map));
      }
      time = result['generated_at'] as String? ?? time;
      next = result['next_cursor'] as String?;
      if (next == null) {
        return CloudReportRows(rows, time);
      }
      if (!seen.add(next)) {
        throw StateError('Cursor báo cáo bị lặp.');
      }
    }
    throw StateError(
      'Báo cáo quá lớn; chọn khoảng ngày hoặc cửa hàng hẹp hơn.',
    );
  }

  Future<ReportData> read(
    ReportRange range,
    String store, {
    bool Function()? isCancelled,
  }) async {
    if (api.token == null) {
      throw StateError('Cần đăng nhập để xem báo cáo online.');
    }
    final first = await api.send(path('/reports/daily', range, store));
    if (first['feed_cursor'] is! String) {
      throw StateError('Thiếu mốc đồng bộ báo cáo.');
    }
    final results = await Future.wait([
      pages(
        '/reports/daily',
        range,
        store,
        first: first,
        isCancelled: isCancelled,
      ),
      pages(
        '/reports/details',
        range,
        store,
        kind: 'stock',
        isCancelled: isCancelled,
      ),
      pages(
        '/reports/details',
        range,
        store,
        kind: 'debts',
        isCancelled: isCancelled,
      ),
      pages(
        '/reports/details',
        range,
        store,
        kind: 'tailoring',
        isCancelled: isCancelled,
      ),
    ]);
    if (isCancelled?.call() == true) {
      throw StateError('Đã đóng báo cáo.');
    }
    final refresh = await api.send(
      path(
        '/reports/refresh',
        range,
        store,
        since: first['feed_cursor'] as String,
      ),
    );
    if (refresh['rows'] is! List) {
      throw StateError('Cloud không xác nhận được mốc báo cáo.');
    }
    final daily = <String, Map<String, Object?>>{};
    void accept(Map<String, Object?> row) {
      daily[jsonEncode([
            row['store_id'],
            row['day'],
            row['school_year'],
            row['school_id'],
          ])] =
          row;
    }

    for (final row in results[0].rows) {
      accept(row);
    }
    for (final row in refresh['rows'] as List) {
      accept(Map<String, Object?>.from(row as Map));
    }
    final totals = <String, BigInt>{},
        labels = <String, String>{},
        dayTotals = <String, Map<String, BigInt>>{};
    for (final row in daily.values) {
      final metrics = Map<String, Object?>.from(row['metrics'] as Map),
          day = row['day'] as String,
          dayMap = dayTotals.putIfAbsent(day, () => {});
      for (final entry in metrics.entries) {
        if (entry.key.startsWith('label|')) {
          labels[entry.key] = entry.value as String;
          continue;
        }
        final value = BigInt.tryParse(entry.value as String);
        if (value == null) {
          throw StateError('Cloud trả số tiền không phải số nguyên.');
        }
        totals[entry.key] = (totals[entry.key] ?? BigInt.zero) + value;
        if (!entry.key.contains('|')) {
          dayMap[entry.key] = (dayMap[entry.key] ?? BigInt.zero) + value;
        }
      }
    }
    BigInt get(String key) => totals[key] ?? BigInt.zero;
    List<List<Object?>> ranking(String prefix, {bool byQuantity = false}) {
      final keys = totals.keys
          .where((k) => k.startsWith('$prefix|'))
          .map((k) => k.split('|')[1])
          .toSet();
      final rows = <List<Object?>>[
        for (final id in keys)
          [
            labels['label|$prefix|$id'] ?? id,
            get('$prefix|$id|quantity'),
            get('$prefix|$id|revenue'),
            get('$prefix|$id|cost'),
            get('$prefix|$id|revenue') - get('$prefix|$id|cost'),
          ],
      ];
      rows.sort(
        (a, b) => (b[byQuantity ? 1 : 2] as BigInt).compareTo(
          a[byQuantity ? 1 : 2] as BigInt,
        ),
      );
      return rows;
    }

    final stores = [
      for (final row in first['stores'] as List)
        Map<String, Object?>.from(row as Map),
    ];
    String storeName(Object? id) =>
        stores.where((s) => s['id'] == id).firstOrNull?['code'] as String? ??
        id.toString();
    BigInt number(Object? value) {
      final parsed = BigInt.tryParse(value as String);
      if (parsed == null) {
        throw StateError('Số báo cáo cloud không hợp lệ.');
      }
      return parsed;
    }

    final stocks = <List<Object?>>[
      for (final r in results[1].rows)
        [
          storeName(r['store_id']),
          r['name'],
          r['size'],
          r['color'],
          number(r['quantity']),
          number(r['reserved']),
          number(r['quantity']) - number(r['reserved']),
          number(r['quantity']) * number(r['unit_cost']),
        ],
    ];
    stocks.sort((a, b) => (b[4] as BigInt).compareTo(a[4] as BigInt));
    var debt = BigInt.zero, overdue = BigInt.zero;
    final debts = <List<Object?>>[];
    final currentDay = DateTime.parse(
      results[2].generatedAt ?? refresh['generated_at'] as String,
    ).toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);
    for (final r in results[2].rows) {
      final value = number(r['amount']), due = r['due_date'] as String;
      final late = due.isNotEmpty && due.compareTo(currentDay) < 0;
      debt += value;
      if (late) {
        overdue += value;
      }
      debts.add([
        storeName(r['store_id']),
        r['code'],
        r['customer_name'],
        value,
        due,
        late ? 'Quá hạn' : 'Chưa quá hạn',
      ]);
    }
    debts.sort((a, b) => (b[3] as BigInt).compareTo(a[3] as BigInt));
    final tailors = <List<Object?>>[
      for (final r in results[3].rows)
        [
          storeName(r['store_id']),
          r['code'],
          r['customer_name'],
          r['due_date'] ?? '',
          ['Mới nhận', 'Đang may', 'Xong', 'Đã giao'][r['status'] as int],
          number(r['amount']),
        ],
    ];
    final days = dayTotals.keys.toList()..sort();
    final summary = <String, BigInt>{
      'revenue': get('revenue'),
      'cost': get('cost'),
      'gross_profit': get('revenue') - get('cost'),
      'quantity': get('quantity'),
      'payment_in': get('payment_in'),
      'payment_out': get('payment_out'),
      'cashflow': get('payment_in') - get('payment_out'),
      'invoices': get('invoices'),
      'returns': get('returns'),
      'tailoring': get('tailoring'),
      'debt': debt,
      'overdue': overdue,
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
          for (final day in days)
            [
              day,
              dayTotals[day]!['revenue'] ?? BigInt.zero,
              dayTotals[day]!['cost'] ?? BigInt.zero,
              (dayTotals[day]!['revenue'] ?? BigInt.zero) -
                  (dayTotals[day]!['cost'] ?? BigInt.zero),
              dayTotals[day]!['payment_in'] ?? BigInt.zero,
              dayTotals[day]!['payment_out'] ?? BigInt.zero,
            ],
        ],
        moneyColumns: {1, 2, 3, 4, 5},
      ),
      'Sản phẩm · lãi gộp': ReportTable(
        ['Sản phẩm', 'SL thuần', 'Doanh thu', 'Giá vốn', 'Lãi gộp'],
        ranking('p'),
        moneyColumns: {2, 3, 4},
      ),
      'Size bán chạy': ReportTable(
        ['Size', 'SL thuần', 'Doanh thu', 'Giá vốn', 'Lãi gộp'],
        ranking('s', byQuantity: true),
        moneyColumns: {2, 3, 4},
      ),
      'Tồn kho hiện tại': ReportTable(
        [
          'Cửa hàng',
          'Sản phẩm',
          'Size',
          'Màu',
          'Tồn thực',
          'Đang giữ',
          'Khả dụng',
          'Giá vốn hiện tại',
        ],
        stocks,
        moneyColumns: {7},
      ),
      'Công nợ hiện tại': ReportTable(
        ['Cửa hàng', 'Chứng từ', 'Khách', 'Còn nợ', 'Hạn trả', 'Trạng thái'],
        debts,
        moneyColumns: {3},
      ),
      'Đơn may riêng': ReportTable(
        [
          'Cửa hàng',
          'Mã',
          'Khách',
          'Hẹn trả',
          'Trạng thái cuối kỳ',
          'Giá trị đơn',
        ],
        tailors,
        moneyColumns: {5},
      ),
      'Hiệu suất nhân viên': ReportTable(
        ['Nhân viên', 'SL thuần', 'Doanh thu', 'Giá vốn', 'Lãi gộp'],
        ranking('e'),
        moneyColumns: {2, 3, 4},
      ),
    };
    return ReportData(
      range,
      summary,
      tables,
      refresh['generated_at'] as String,
      storeLabel: stores.length == 1
          ? '${stores.single['code']} · ${stores.single['name']}'
          : 'Toàn hệ thống · ${stores.length} cửa hàng',
    );
  }
}
