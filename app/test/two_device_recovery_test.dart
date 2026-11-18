import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

import 'fixtures.dart';

class _FixtureApi extends CloudApi {
  _FixtureApi(super.baseUrl, {required super.client}) {
    token = 'fixture-interactive';
    currentUserId = 'u1';
  }

  @override
  Future<String?> syncTokenFor(
    String user,
    String store,
    String device,
  ) async => 'fixture-sync';
}

/// Protocol fixture, not a replacement implementation of the API: it records
/// exact client mutations and echoes their records. Business rules still run in
/// the actual LocalService/SQLite triggers. Real server replay is tested in API.
class _ProtocolFixture {
  final accepted = <String, String>{};
  final attempts = <String, int>{};
  final events = <Map<String, Object?>>[];
  bool loseNextAck = false;

  Future<http.Response> handle(http.Request request) async {
    Map<String, Object?> result;
    switch (request.url.path) {
      case '/directory':
        result = {'stores': [], 'devices': [], 'users': []};
      case '/sync/push':
        final mutations =
            (jsonDecode(request.body) as Map)['mutations'] as List;
        for (final mutation in mutations) {
          final id = mutation['id'] as String;
          final payload = jsonEncode(mutation['records']);
          attempts[id] = (attempts[id] ?? 0) + 1;
          if (accepted.containsKey(id)) {
            expect(
              accepted[id],
              payload,
              reason: 'Retry must keep exact bytes',
            );
            continue;
          }
          accepted[id] = payload;
          for (final record in mutation['records'] as List) {
            if (record['table'] == 'audit_logs') continue;
            events.add({
              'server_seq': events.length + 1,
              'entity_type': record['table'],
              'payload': jsonEncode(record['row']),
            });
          }
        }
        if (loseNextAck) {
          loseNextAck = false;
          throw TimeoutException('Fixture: committed, response lost');
        }
        result = {
          'acknowledged': [for (final m in mutations) m['id']],
        };
      case '/sync/pull':
        final cursor = int.parse(request.url.queryParameters['cursor']!);
        final store = request.url.queryParameters['scope'] == 'store';
        result = {
          'events': store
              ? events.where((e) => (e['server_seq'] as int) > cursor).toList()
              : [],
          'cursor': store ? events.length : cursor,
          'has_more': false,
        };
      case '/payroll/pull':
        result = {'events': [], 'cursor': 0, 'has_more': false};
      default:
        throw StateError('Unexpected protocol request: ${request.url}');
    }
    return http.Response(
      jsonEncode(result),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  SyncEngine engine(LocalService service) => SyncEngine(
    service,
    _FixtureApi('http://fixture', client: MockClient(handle)),
  );
}

LocalService _service(AppDatabase db, String device) =>
    LocalService(db, deviceId: device, clock: () => DateTime.utc(2026, 11, 15))
      ..session = LocalSession(
        userId: 'u1',
        name: 'Chủ',
        role: Role.owner,
        storeId: 'store-cn01',
        deviceId: device,
        expiresAt: DateTime.utc(2027),
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Hai file SQLite offline hội tụ sau mất ACK, đóng/mở lại và replay feed', () async {
    // Deliberately separate executors/files, as on independent devices.
    final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
    });
    final folder = await Directory.systemTemp.createTemp(
      'ngoc-thanh-two-devices-',
    );
    final fileA = File('${folder.path}/a.sqlite');
    final fileB = File('${folder.path}/b.sqlite');
    var dbA = AppDatabase(NativeDatabase(fileA));
    final dbB = AppDatabase(NativeDatabase(fileB));
    final engines = <SyncEngine>[];
    addTearDown(() async {
      for (final engine in engines) {
        await engine.pauseAndDrain();
        engine.dispose();
      }
      await dbA.close();
      await dbB.close();
      await folder.delete(recursive: true);
    });
    var a = await salesFixture(database: dbA);
    await dbA.execute(
      "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('device-b2','store-cn01','B2','Máy B2','approved','2026-11-15')",
    );
    await _service(dbA, 'device-b2').adjustStock('v1', 4, 'Tồn đầu máy B');
    // A shared, already-synced baseline: A owns 10, B owns 4. Each file has
    // its own ledger/cache/counter/outbox; no database is shared at runtime.
    for (final table in [
      'stores',
      'devices',
      'users',
      'products',
      'product_variants',
      'stock_movements',
      'audit_logs',
    ]) {
      for (final row in await dbA.rows('SELECT * FROM $table')) {
        await dbB.execute(
          'INSERT INTO $table (${row.keys.join(',')}) VALUES (${row.keys.map((_) => '?').join(',')})',
          row.values.toList(),
        );
      }
    }
    await dbA.execute('DELETE FROM outbox');
    final b = _service(dbB, 'device-b2');
    final first = await a.sell(
      items: [const CartItem('v1', 3)],
      discount: 0,
      received: 300000,
      method: 'cash',
    );
    final second = await b.sell(
      items: [const CartItem('v1', 4)],
      discount: 0,
      received: 400000,
      method: 'bank',
    );
    expect(first.code, 'HD-CN01-A2-20261115-001');
    expect(second.code, 'HD-CN01-B2-20261115-001');
    expect(first.id, isNot(second.id));
    final before = await dbB.rows('SELECT * FROM outbox ORDER BY id');
    await expectLater(
      b.sell(
        items: [const CartItem('v1', 1)],
        discount: 0,
        received: 100000,
        method: 'cash',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('phân bổ'),
        ),
      ),
    );
    expect(await dbB.rows('SELECT * FROM outbox ORDER BY id'), before);
    expect(await dbB.rows('SELECT id FROM documents'), hasLength(1));
    final cloud = _ProtocolFixture();
    final engineB = cloud.engine(b)..start();
    engines.add(engineB);
    await engineB.sync();
    expect(engineB.status, SyncStatus.synced, reason: engineB.detail);
    cloud.loseNextAck = true;
    final engineA = cloud.engine(a)..start();
    engines.add(engineA);
    final pendingA = await dbA.rows('SELECT id FROM outbox ORDER BY id');
    await engineA.sync();
    expect(engineA.status, SyncStatus.offline, reason: engineA.detail);
    expect(await dbA.rows('SELECT id FROM outbox ORDER BY id'), pendingA);
    await engineA.pauseAndDrain();
    engineA.dispose();
    engines.remove(engineA);
    await dbA.close();
    dbA = AppDatabase(NativeDatabase(fileA));
    a = _service(dbA, 'device-a2');
    final replay = await a.sell(
      items: [const CartItem('v1', 3)],
      discount: 0,
      received: 300000,
      method: 'cash',
      commandId: first.id,
    );
    expect(replay.id, first.id);
    expect(await dbA.rows('SELECT id FROM outbox ORDER BY id'), pendingA);
    final retryA = cloud.engine(a)..start();
    engines.add(retryA);
    await retryA.sync();
    expect(retryA.status, SyncStatus.synced, reason: retryA.detail);
    expect(cloud.attempts.values, contains(2));
    await engineB.sync();
    expect(engineB.status, SyncStatus.synced, reason: engineB.detail);
    // Re-deliver previously seen events to exercise local idempotency too.
    await dbA.execute(
      "UPDATE sync_cursors SET server_seq=0 WHERE store_id='store-cn01'",
    );
    await retryA.sync();
    for (final db in [dbA, dbB]) {
      expect(await db.rows('SELECT id FROM outbox'), isEmpty);
      expect(await db.rows('SELECT id FROM documents'), hasLength(2));
      expect(await db.rows('SELECT id FROM payments'), hasLength(2));
      expect(
        (await db.rows('SELECT SUM(amount) AS n FROM payments')).single['n'],
        700000,
      );
      expect(
        (await db.rows('SELECT quantity FROM stock_balances'))
            .single['quantity'],
        7,
      );
      expect(
        (await db.rows('SELECT SUM(quantity) AS n FROM stock_movements'))
            .single['n'],
        7,
      );
      expect(await db.rows('SELECT id FROM stock_movements'), hasLength(4));
      expect(
        (await db.rows('SELECT value FROM document_counters')).single['value'],
        1,
      );
      expect(
        (await db.rows('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rows('PRAGMA foreign_key_check'), isEmpty);
    }
  });
}
