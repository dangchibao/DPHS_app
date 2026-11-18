import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

/// SQL migrations được giữ cùng schema D1, ngăn hai nền tảng lệch nhau.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor, {this.filePath, this.onClosed});
  final String? filePath;
  final Future<void> Function()? onClosed;
  bool isClosed = false;
  bool _released = false;
  Future<void> releaseFileLock() async {
    if (!_released) {
      _released = true;
      await onClosed?.call();
    }
  }

  @override
  Future<void> close({bool releaseLock = true}) async {
    if (!isClosed) {
      await super.close();
      isClosed = true;
    }
    if (releaseLock) await releaseFileLock();
  }

  static const currentSchemaVersion = 30;
  @override
  int get schemaVersion => currentSchemaVersion;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final file in [
        '0001_foundation.sql',
        '0002_local_core.sql',
        '0003_auth_and_settings.sql',
        '0004_sync.sql',
        '0005_sales.sql',
        '0006_operations.sql',
        '0007_sync_capabilities.sql',
        '0008_price_history.sql',
        '0009_collections.sql',
        '0010_schools.sql',
        '0011_combos.sql',
        '0012_audit_receipts.sql',
        '0013_commercial_rules.sql',
        '0014_tailoring.sql',
        '0015_returns.sql',
        '0016_free_budget.sql',
        '0017_reservations.sql',
        '0018_device_enrollment.sql',
        '0019_size_rules.sql',
        '0020_transfers.sql',
        '0021_attendance.sql',
        '0022_payroll.sql',
        '0023_reports_access.sql',
        '0024_cloud_reports.sql',
        '0025_web_devices.sql',
        '0026_bank_accounts.sql',
        '0027_product_media.sql',
        '0028_staff_handoffs.sql',
        '0029_stock_thresholds.sql',
        '0030_audit_archives.sql',
      ]) {
        await applySql(await rootBundle.loadString('assets/migrations/$file'));
      }
    },
    onUpgrade: (_, from, to) async {
      final files = [
        '0001_foundation.sql',
        '0002_local_core.sql',
        '0003_auth_and_settings.sql',
        '0004_sync.sql',
        '0005_sales.sql',
        '0006_operations.sql',
        '0007_sync_capabilities.sql',
        '0008_price_history.sql',
        '0009_collections.sql',
        '0010_schools.sql',
        '0011_combos.sql',
        '0012_audit_receipts.sql',
        '0013_commercial_rules.sql',
        '0014_tailoring.sql',
        '0015_returns.sql',
        '0016_free_budget.sql',
        '0017_reservations.sql',
        '0018_device_enrollment.sql',
        '0019_size_rules.sql',
        '0020_transfers.sql',
        '0021_attendance.sql',
        '0022_payroll.sql',
        '0023_reports_access.sql',
        '0024_cloud_reports.sql',
        '0025_web_devices.sql',
        '0026_bank_accounts.sql',
        '0027_product_media.sql',
        '0028_staff_handoffs.sql',
        '0029_stock_thresholds.sql',
        '0030_audit_archives.sql',
      ];
      if (from < 1 || to > files.length || from >= to) {
        throw StateError('Chưa hỗ trợ migration $from → $to');
      }
      for (var version = from; version < to; version++) {
        await applySql(
          await rootBundle.loadString('assets/migrations/${files[version]}'),
        );
      }
      // Bản cũ có thể chưa biết một loại feed; replay từ đầu bằng ID idempotent.
      await customStatement('DELETE FROM sync_cursors');
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> applySql(String sql) async {
    // Marker giữ nguyên body trigger nhiều dấu chấm phẩy.
    for (final part in sql.split('-- @statement')) {
      if (part.trim().isEmpty) continue;
      if (part.contains('CREATE TRIGGER')) {
        await customStatement(part.trim());
      } else {
        for (final statement in splitSchemaStatements(part)) {
          await customStatement(statement);
        }
      }
    }
  }

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async => (await customSelect(
    sql,
    variables: args.map((e) => Variable(e)).toList(),
  ).get()).map((e) => Map<String, Object?>.from(e.data)).toList();

  Future<void> execute(String sql, [List<Object?> args = const []]) =>
      customStatement(sql, args);
}

/// Tách statement ngoài chuỗi/comment. Body trigger được giữ nguyên bởi marker.
Iterable<String> splitSchemaStatements(String sql) sync* {
  String? quote;
  var lineComment = false, blockComment = false, hasToken = false, start = 0;
  for (var i = 0; i < sql.length; i++) {
    final c = sql[i], next = i + 1 < sql.length ? sql[i + 1] : '';
    if (lineComment) {
      if (c == '\n') {
        lineComment = false;
      }
      continue;
    }
    if (blockComment) {
      if (c == '*' && next == '/') {
        blockComment = false;
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (c == quote) {
        if (next == quote) {
          i++;
        } else {
          quote = null;
        }
      }
      continue;
    }
    if (c == '-' && next == '-') {
      lineComment = true;
      i++;
      continue;
    }
    if (c == '/' && next == '*') {
      blockComment = true;
      i++;
      continue;
    }
    if (c == "'" || c == '"' || c == '`' || c == '[') {
      quote = c == '[' ? ']' : c;
      hasToken = true;
      continue;
    }
    if (c == ';') {
      if (hasToken) {
        yield sql.substring(start, i).trim();
      }
      start = i + 1;
      hasToken = false;
      continue;
    }
    if (c.trim().isNotEmpty) {
      hasToken = true;
    }
  }
  if (hasToken) {
    yield sql.substring(start).trim();
  }
}
