import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../local_service.dart';
import '../auth/permissions.dart';
import 'cloud_api.dart';
import '../media/media_service.dart';

const maxSyncMutations = 3;
const payrollFeedTables = {
  'compensation_versions',
  'payroll_runs',
  'payroll_voids',
  'payroll_results',
  'payroll_reconciliations',
};

enum SyncStatus {
  synced,
  syncing,
  offline,
  cloudLimit,
  temporaryError,
  needsLogin,
  conflict,
}

class SyncEngine extends ChangeNotifier {
  SyncEngine(this.service, this.api);
  final LocalService service;
  final CloudApi api;
  SyncStatus status = SyncStatus.offline;
  int pending = 0, failures = 0;
  int mediaPending = 0;
  String? detail;
  Timer? _poll, _debounce, _retry;
  bool _running = false, _stopped = true;
  DateTime? nextRetryAt;
  bool _disposed = false;
  bool mediaEnabled = false;
  Completer<void>? _completion;
  Future<void> pauseAndDrain() async {
    stop();
    await _completion?.future;
  }

  String get label => switch (status) {
    SyncStatus.synced => 'Đã đồng bộ',
    SyncStatus.syncing => 'Đang đồng bộ',
    SyncStatus.offline => 'Mất mạng',
    SyncStatus.cloudLimit => 'Cloud đạt giới hạn',
    SyncStatus.temporaryError => 'Cloud tạm thời lỗi',
    SyncStatus.needsLogin => 'Cần đăng nhập cloud',
    SyncStatus.conflict => 'Cần kiểm tra đồng bộ',
  };
  void start() {
    _stopped = false;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => sync());
    schedule();
  }

  void schedule() {
    if (_stopped) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), sync);
  }

  Future<void> count() async {
    if (_disposed || service.db.isClosed) return;
    pending =
        (await service.db.rows(
              'SELECT COUNT(*) AS n FROM outbox WHERE store_id=?',
              [service.storeId],
            )).single['n']
            as int;
    mediaPending =
        (await service.db.rows(
              'SELECT COUNT(*) AS n FROM media_outbox WHERE store_id=? AND device_id=?',
              [service.storeId, service.deviceId],
            )).single['n']
            as int;
    if (!_disposed) notifyListeners();
  }

  Future<void> sync() async {
    if (_running || _stopped) return;
    if (nextRetryAt?.isAfter(DateTime.now()) ?? false) return;
    if (api.token == null && !api.hasPendingLogin) {
      status = SyncStatus.needsLogin;
      await count();
      return;
    }
    _running = true;
    _completion = Completer<void>();
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      if (api.token == null) {
        final remote = await api.reconnect();
        if (remote == null) {
          throw const CloudError(
            401,
            'UNAUTHENTICATED',
            'Cần đăng nhập cloud.',
          );
        }
        await service.acceptOnlineReconnect(remote);
      }
      final directory = await api.send('/directory');
      mediaEnabled = directory['media_enabled'] == true;
      final frozenActor = (directory['users'] as List).any(
        (r) =>
            (r as Map)['frozen'] == 1 &&
            (r['id'] == api.currentUserId ||
                r['id'] == service.session?.userId),
      );
      final handoffs = [
        for (final r in directory['handoffs'] as List? ?? [])
          Map<String, Object?>.from(r as Map),
      ];
      var accessChanged = false;
      await service.db.transaction(() async {
        await service.acceptAuditHead(directory['audit_head']);
        if (directory.containsKey('transfer_targets')) {
          await service.db.execute(
            "INSERT INTO local_settings VALUES ('transfer_targets',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [jsonEncode(directory['transfer_targets'] ?? [])],
          );
        }
        for (final raw in directory['stores'] as List) {
          final row = Map<String, Object?>.from(raw as Map);
          await service.db.execute(
            'INSERT INTO stores VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,active=excluded.active',
            [
              row['id'],
              row['code'],
              row['name'],
              row['active'],
              row['created_at'],
            ],
          );
        }
        for (final raw in directory['devices'] as List) {
          final row = Map<String, Object?>.from(raw as Map);
          if (row['store_id'] != service.storeId) {
            throw StateError('Thiết bị khác cửa hàng.');
          }
          await service.db.execute(
            'INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,name=excluded.name',
            [
              row['id'],
              row['store_id'],
              row['code'],
              row['name'],
              row['status'],
              row['created_at'],
            ],
          );
        }
        for (final raw in directory['users'] as List) {
          final row = Map<String, Object?>.from(raw as Map);
          await service.db.execute(
            'INSERT INTO users VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name,active=excluded.active,must_change_password=excluded.must_change_password,updated_at=excluded.updated_at',
            [
              row['id'],
              row['username'],
              row['display_name'],
              '',
              'AAAAAAAAAAAAAAAAAAAAAA==',
              row['active'],
              row['must_change_password'],
              row['updated_at'],
            ],
          );
          await service.db.execute(
            'INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?) ON CONFLICT(store_id,user_id) DO UPDATE SET role=excluded.role,active=excluded.active,updated_at=excluded.updated_at',
            [
              service.uuid.v7(),
              service.storeId,
              row['id'],
              row['role'],
              row['assignment_active'],
              row['updated_at'],
            ],
          );
          if (row['frozen'] == 1) {
            await service.db.execute('UPDATE users SET active=0 WHERE id=?', [
              row['id'],
            ]);
            await service.db.execute(
              'UPDATE employee_store_assignments SET active=0 WHERE store_id=? AND user_id=?',
              [service.storeId, row['id']],
            );
            await service.db.execute('DELETE FROM local_settings WHERE key=?', [
              'grant:${row['id']}',
            ]);
          }
        }
        final actor = service.session;
        if (actor != null) {
          if ((directory['users'] as List).any(
            (r) => (r as Map)['id'] == actor.userId && r['frozen'] == 1,
          )) {
            service.session = LocalSession(
              userId: actor.userId,
              name: actor.name,
              role: actor.role,
              storeId: actor.storeId,
              deviceId: actor.deviceId,
              expiresAt: service.clock(),
            );
          }
          final current =
              (directory['users'] as List)
                      .where((raw) => (raw as Map)['id'] == actor.userId)
                      .firstOrNull
                  as Map?;
          if (current != null &&
              (current['active'] != 1 ||
                  current['assignment_active'] != 1 ||
                  current['role'] != actor.role.name)) {
            accessChanged = true;
            await service.db.execute('DELETE FROM local_settings WHERE key=?', [
              'grant:${actor.userId}',
            ]);
            service.session = LocalSession(
              userId: actor.userId,
              name: actor.name,
              role: actor.role,
              storeId: actor.storeId,
              deviceId: actor.deviceId,
              expiresAt: service.clock(),
            );
          }
        }
      });
      if (accessChanged) {
        throw const CloudError(
          401,
          'ACCESS_CHANGED',
          'Quyền hoặc phân công đã thay đổi. Đăng nhập lại để xác nhận quyền mới.',
        );
      }
      // Đọc tối đa từng trang; dependencies cho phép gửi danh mục trước giao dịch tham chiếu.
      for (var page = 0; page < 10; page++) {
        final queue = await service.db.rows(
          "SELECT * FROM outbox WHERE store_id=? ORDER BY priority,CASE WHEN entity_type='audit' THEN json_extract(payload,'\$[0].row.chain_index') ELSE 0 END,created_at,id LIMIT 200",
          [service.storeId],
        );
        if (queue.isEmpty) break;
        final byId = {for (final row in queue) row['id'] as String: row};
        final ordered = <Map<String, Object?>>[],
            visiting = <String>{},
            visited = <String>{};
        Future<void> visit(Map<String, Object?> row) async {
          final id = row['id'] as String;
          if (visited.contains(id)) return;
          if (!visiting.add(id)) {
            throw StateError('Vòng phụ thuộc trong hàng đợi.');
          }
          for (final dependency
              in jsonDecode(row['dependencies_json'] as String) as List) {
            var dep = byId[dependency];
            if (dep == null) {
              final found = await service.db.rows(
                'SELECT * FROM outbox WHERE store_id=? AND id=?',
                [service.storeId, dependency],
              );
              dep = found.isEmpty ? null : found.single;
            }
            if (dep != null) await visit(dep);
          }
          visiting.remove(id);
          visited.add(id);
          ordered.add(row);
        }

        for (final row in queue.take(maxSyncMutations)) {
          await visit(row);
        }
        // Giới hạn theo byte để không vượt CPU/body trên Free.
        final batch = <Map<String, Object?>>[];
        final privatePayroll =
            ordered.first['entity_type'] == 'payroll_command';
        final actorId = ordered.first['actor_id'] as String?;
        final grant = actorId == null
            ? api.token
            : await api.syncTokenFor(
                actorId,
                service.storeId,
                service.deviceId,
              );
        if (grant == null) {
          throw StateError(
            'Cần $actorId đăng nhập lại để đồng bộ hàng đợi của tài khoản này.',
          );
        }
        var bytes = 0;
        for (final row in ordered) {
          if (row['actor_id'] != actorId) break;
          if ((row['entity_type'] == 'payroll_command') != privatePayroll ||
              (privatePayroll && batch.isNotEmpty)) {
            break;
          }
          final records = jsonDecode(row['payload'] as String);
          final mutation = {'id': row['id'], 'records': records};
          final size = utf8.encode(jsonEncode(mutation)).length;
          if (size > 200000) {
            throw StateError('Một giao dịch quá lớn để đồng bộ.');
          }
          if (batch.isNotEmpty &&
              (bytes + size > 200000 || batch.length >= maxSyncMutations)) {
            break;
          }
          batch.add(mutation);
          bytes += size;
        }
        late Map<String, Object?> response;
        try {
          response = await api.send(
            privatePayroll ? '/payroll/push' : '/sync/push',
            body: {'mutations': batch},
            tokenOverride: grant,
          );
        } on CloudError catch (error) {
          if (error.status == 401) {
            throw StateError(
              'Cần $actorId đăng nhập lại để gửi thay đổi chưa đồng bộ.',
            );
          }
          rethrow;
        }
        final acknowledged = (response['acknowledged'] as List).cast<String>();
        final sent = batch.map((e) => e['id']).toSet();
        if (acknowledged.any((id) => !sent.contains(id)) ||
            acknowledged.isEmpty) {
          throw StateError('Cloud xác nhận batch không hợp lệ.');
        }
        await service.db.transaction(() async {
          for (final id in acknowledged) {
            await service.db.execute(
              'DELETE FROM outbox WHERE store_id=? AND id=?',
              [service.storeId, id],
            );
          }
        });
      }
      var caughtUp = true;
      for (final scope in [
        'global',
        'store',
        if (!frozenActor &&
            [Role.owner, Role.manager].contains(service.session?.role))
          'audit',
        if (!frozenActor && service.session?.can(Permission.attendance) == true)
          'attendance',
        if (!frozenActor && service.session?.can(Permission.payroll) == true)
          'payroll',
      ]) {
        var remaining = false;
        final key = scope == 'global'
            ? '*'
            : scope == 'store'
            ? service.storeId
            : '$scope:${service.storeId}';
        for (var page = 0; page < 10; page++) {
          final cursors = await service.db.rows(
            'SELECT server_seq FROM sync_cursors WHERE store_id=?',
            [key],
          );
          final cursor = cursors.isEmpty
              ? 0
              : cursors.single['server_seq'] as int;
          final response = await api.send(
            scope == 'payroll'
                ? '/payroll/pull?cursor=$cursor'
                : '/sync/pull?scope=$scope&cursor=$cursor',
          );
          final next = response['cursor'] as int;
          if (next < cursor) throw StateError('Con trỏ cloud đi lùi.');
          await service.db.transaction(() async {
            for (final raw in response['events'] as List) {
              final event = Map<String, Object?>.from(raw as Map),
                  table = event['entity_type'] as String;
              final row = Map<String, Object?>.from(
                jsonDecode(event['payload'] as String) as Map,
              );
              if (scope == 'payroll'
                  ? !payrollFeedTables.contains(table)
                  : payrollFeedTables.contains(table)) {
                throw StateError('Cloud trả sai kênh dữ liệu lương.');
              }
              if (![
                ...payrollFeedTables,
                'products',
                'product_variants',
                'stock_movements',
                'audit_logs',
                'customers',
                'documents',
                'invoice_lines',
                'payments',
                'receivable_entries',
                'schools',
                'school_classes',
                'students',
                'combo_rules',
                'commercial_rules',
                'tailoring_rules',
                'size_rules',
                'bank_accounts',
                'stock_threshold_rules',
                'media_objects',
                'transfer_events',
                'transfer_receipts',
                'transfer_offers',
                'transfer_deliveries',
                'attendance_entries',
                'attendance_rejections',
                'payroll_locks',
                'payroll_lock_releases',
                'document_events',
                'return_lines',
                'reservation_lines',
                'reservation_events',
                'receivable_adjustments',
              ].contains(table)) {
                throw StateError('Thực thể chưa được hỗ trợ.');
              }
              if (row.containsKey('store_id') &&
                  row['store_id'] != service.storeId) {
                throw StateError('Cloud trả sai phạm vi cửa hàng.');
              }
              final columns = row.keys.toList();
              if (columns.any((key) => !RegExp(r'^[a-z_]+$').hasMatch(key))) {
                throw StateError('Tên trường không hợp lệ.');
              }
              if (table == 'products' ||
                  table == 'product_variants' ||
                  table == 'customers' ||
                  [
                    'schools',
                    'school_classes',
                    'students',
                    'combo_rules',
                    'commercial_rules',
                    'tailoring_rules',
                    'size_rules',
                    'bank_accounts',
                  ].contains(table)) {
                await service.db.execute(
                  'INSERT INTO $table (${columns.join(',')}) VALUES (${columns.map((_) => '?').join(',')}) ON CONFLICT(id) DO UPDATE SET ${columns.where((c) => c != 'id').map((c) => '$c=excluded.$c').join(',')} WHERE excluded.lww_key>$table.lww_key',
                  row.values.toList(),
                );
              } else {
                await service.db.execute(
                  'INSERT INTO $table (${columns.join(',')}) VALUES (${columns.map((_) => '?').join(',')}) ON CONFLICT(id) DO NOTHING',
                  row.values.toList(),
                );
              }
              if (table == 'audit_logs' && row['server_time'] != null) {
                await service.db.execute(
                  'INSERT OR IGNORE INTO local_audit_receipts(store_id,audit_id,received_at) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM audit_logs WHERE store_id=? AND id=? AND server_time IS NULL)',
                  [
                    service.storeId,
                    row['id'],
                    row['server_time'],
                    service.storeId,
                    row['id'],
                  ],
                );
              }
              if (table == 'attendance_entries') {
                await service.db.execute(
                  'INSERT OR IGNORE INTO local_attendance_receipts VALUES(?,?,?)',
                  [service.storeId, row['id'], service.now],
                );
              }
            }
            await service.db.execute(
              'INSERT INTO sync_cursors VALUES (?,?) ON CONFLICT(store_id) DO UPDATE SET server_seq=excluded.server_seq',
              [key, next],
            );
          });
          remaining = response['has_more'] == true;
          if (!remaining) break;
        }
        if (remaining) caughtUp = false;
      }
      await count();
      if (caughtUp && pending == 0 && service.restoreBlocked) {
        final reason = await service.db.rows(
          "SELECT value FROM local_settings WHERE key='restore_reason'",
        );
        if (reason.isEmpty || reason.single['value'] != 'identity') {
          await service.db.transaction(() async {
            final documents = await service.db.rows(
              'SELECT type,code FROM documents WHERE store_id=? AND device_id=?',
              [service.storeId, service.deviceId],
            );
            for (final document in documents) {
              final parts = (document['code'] as String).split('-');
              if (parts.length < 5) {
                throw StateError('Mã chứng từ không hợp lệ khi đối soát.');
              }
              final day = parts[parts.length - 2],
                  number = int.parse(parts.last);
              await service.db.execute(
                'INSERT INTO document_counters VALUES (?,?,?,?,?) ON CONFLICT(store_id,device_id,type,day) DO UPDATE SET value=MAX(value,excluded.value)',
                [
                  service.storeId,
                  service.deviceId,
                  document['type'],
                  day,
                  number,
                ],
              );
            }
            await service.db.execute(
              "UPDATE local_settings SET value='0' WHERE key='restore_blocked'",
            );
            final finalizedDrafts = await service.db.rows(
              "SELECT h.id FROM held_carts h JOIN documents d ON d.store_id=h.store_id AND json_extract(d.metadata_json,'\$.held_cart_id')=h.id WHERE h.store_id=? AND d.device_id=? AND d.type='HD' AND d.kind='sale'",
              [service.storeId, service.deviceId],
            );
            for (final draft in finalizedDrafts) {
              await service.db.execute(
                'DELETE FROM held_carts WHERE store_id=? AND id=?',
                [service.storeId, draft['id']],
              );
            }
            await service.audit(
              'RESTORE_RECONCILED',
              'device',
              service.deviceId,
              reason: 'Đã kéo hết dữ liệu cloud và nâng bộ đếm chứng từ',
              severity: 'critical',
              changes: {'closed_held_carts': finalizedDrafts.length},
            );
          });
          service.restoreBlocked = false;
        }
      }
      failures = 0;
      if (caughtUp &&
          (await service.db.rows(
            'SELECT id FROM outbox WHERE store_id=? LIMIT 1',
            [service.storeId],
          )).isEmpty) {
        final cursor =
            (await service.db.rows(
              'SELECT server_seq FROM sync_cursors WHERE store_id=?',
              [service.storeId],
            )).firstOrNull?['server_seq'] ??
            0;
        for (final request in handoffs.where((h) => h['requires_ack'] == 1)) {
          try {
            await api.send(
              '/staff/handoffs/ack',
              body: {'id': request['id'], 'drained': true, 'cursor': cursor},
            );
          } on CloudError catch (error) {
            if (error.status != 409) rethrow;
          }
        }
      }
      if (caughtUp &&
          (await service.db.rows(
            'SELECT id FROM outbox WHERE store_id=? LIMIT 1',
            [service.storeId],
          )).isEmpty) {
        await service.syncProductImages(enabled: mediaEnabled);
      }
      await count();
      nextRetryAt = null;
      if (caughtUp &&
          !frozenActor &&
          pending == 0 &&
          directory['schema_version'] is int &&
          (directory['schema_version'] as int) >= 22) {
        final day = service
            .clock()
            .toUtc()
            .add(const Duration(hours: 7))
            .toIso8601String()
            .substring(0, 10);
        final checkpointKey =
            'checkpoint:${service.storeId}:${service.deviceId}:$day';
        if ((await service.db.rows(
              'SELECT value FROM local_settings WHERE key=?',
              [checkpointKey],
            )).isEmpty &&
            (await service.db.rows(
              'SELECT id FROM outbox WHERE store_id=? LIMIT 1',
              [service.storeId],
            )).isEmpty) {
          final cursor =
              (await service.db.rows(
                'SELECT server_seq FROM sync_cursors WHERE store_id=?',
                [service.storeId],
              )).firstOrNull?['server_seq'] ??
              0;
          try {
            final receipt = await api.send(
              '/sync/checkpoint',
              body: {'drained': true, 'cursor': cursor},
            );
            if (receipt['received_at'] is! String) {
              throw StateError('Biên nhận đối soát không hợp lệ.');
            }
            await service.db.execute(
              'INSERT OR IGNORE INTO local_settings VALUES(?,?)',
              [checkpointKey, receipt['received_at']],
            );
          } on CloudError catch (error) {
            if (error.status != 409) rethrow;
          }
        }
      }
      detail = null;
      status = caughtUp && pending == 0
          ? SyncStatus.synced
          : SyncStatus.syncing;
      if (status == SyncStatus.syncing) {
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 10), sync);
      }
    } on CloudError catch (error) {
      detail = error.message;
      status =
          ['CLOUD_LIMIT', 'CLOUD_CPU_LIMIT'].contains(error.code) ||
              error.status == 429
          ? SyncStatus.cloudLimit
          : error.status == 401
          ? SyncStatus.needsLogin
          : error.status == 409 || error.status == 403 || error.status == 400
          ? SyncStatus.conflict
          : SyncStatus.temporaryError;
      if (status == SyncStatus.needsLogin) {
        final actor = service.session;
        if (actor != null) {
          await service.db.execute('DELETE FROM local_settings WHERE key=?', [
            'grant:${actor.userId}',
          ]);
          service.session = LocalSession(
            userId: actor.userId,
            name: actor.name,
            role: actor.role,
            storeId: actor.storeId,
            deviceId: actor.deviceId,
            expiresAt: service.clock(),
          );
        }
      }
      if (error.code == 'CLOUD_LIMIT') {
        final now = DateTime.now().toUtc();
        nextRetryAt = DateTime.utc(
          now.year,
          now.month,
          now.day + 1,
        ).add(Duration(seconds: 5 + Random().nextInt(30)));
        _retry?.cancel();
        _retry = Timer(nextRetryAt!.difference(now), sync);
      } else if (status == SyncStatus.cloudLimit ||
          status == SyncStatus.temporaryError) {
        _backoff();
      }
    } on TimeoutException {
      status = SyncStatus.offline;
      _backoff();
    } catch (error) {
      status = error is StateError ? SyncStatus.conflict : SyncStatus.offline;
      detail = error.toString();
      if (status == SyncStatus.offline) _backoff();
    } finally {
      _running = false;
      _completion?.complete();
      _completion = null;
      if (!_disposed) await count();
    }
  }

  void _backoff() {
    failures++;
    final seconds =
        min(900, 5 * pow(2, min(failures, 8)).toInt()) + Random().nextInt(5);
    nextRetryAt = DateTime.now().add(Duration(seconds: seconds));
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), sync);
  }

  void stop() {
    _stopped = true;
    _poll?.cancel();
    _debounce?.cancel();
    _retry?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    api.close();
    super.dispose();
  }
}
