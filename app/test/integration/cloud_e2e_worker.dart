import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/catalog/catalog_service.dart';
import 'package:ngoc_thanh_pos/features/debt/debt_service.dart';
import 'package:ngoc_thanh_pos/features/devices/device_enrollment_service.dart';
import 'package:ngoc_thanh_pos/features/pos/sales_service.dart';

class _NetworkGate extends http.BaseClient {
  final _inner = http.Client();
  bool offline = false, dropNextPushAck = false;
  int requests = 0, droppedAcks = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw const SocketException('Fixture offline');
    requests++;
    final response = await _inner.send(request);
    if (dropNextPushAck &&
        request.url.path == '/sync/push' &&
        response.statusCode == 200) {
      dropNextPushAck = false;
      droppedAcks++;
      await response.stream.drain<void>();
      throw const SocketException('Fixture: real server committed; ACK lost');
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Native POS offline → Cloudflare thật → phục hồi lost ACK và công nợ', () async {
    final raw = Platform.environment['NT_CLOUD_E2E_CONFIG'];
    final password = Platform.environment['PROVISION_OWNER_PASSWORD'];
    if (raw == null || password == null) {
      throw StateError('Chỉ chạy qua quy trình cloud QA có xác nhận đích.');
    }
    final context = jsonDecode(raw) as Map<String, dynamic>;
    final origin = context['origin'] as String;
    if (origin != 'https://ngoc-thanh-pos-e2e.ngoc-thanh-161df6.workers.dev') {
      throw StateError('Chỉ cho phép endpoint QA riêng.');
    }
    // No real Windows secure storage or user SQLite is opened. The mock models
    // independent installation IDs while all app/cloud business code is real.
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() {
      HttpOverrides.global = previousHttp;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
    });
    final folder = await Directory.systemTemp.createTemp('nt-cloud-e2e-');
    final fileA = File('${folder.path}/a.sqlite');
    var dbA = AppDatabase(NativeDatabase(fileA));
    final dbB = AppDatabase(NativeDatabase(File('${folder.path}/b.sqlite')));
    final admin = CloudApi(origin)..token = context['adminToken'] as String;
    var gateA = _NetworkGate();
    final gateB = _NetworkGate();
    var apiA = CloudApi(origin, client: gateA);
    final apiB = CloudApi(origin, client: gateB);
    final engines = <SyncEngine>[];
    var passed = false;
    addTearDown(() async {
      for (final engine in engines) {
        await engine.pauseAndDrain();
        engine.dispose();
      }
      admin.close();
      await dbA.close();
      await dbB.close();
      if (passed) {
        await folder.delete(recursive: true);
      } else {
        stdout.writeln('QA failure evidence retained: ${folder.path}');
      }
    });
    final store = context['storeId'] as String;
    var a = LocalService(
      dbA,
      storeId: store,
      deviceId: context['a']['id'] as String,
    );
    final b = LocalService(
      dbB,
      storeId: store,
      deviceId: context['b']['id'] as String,
    );
    Future<void> enroll(
      LocalService service,
      CloudApi api,
      Map<String, dynamic> device,
    ) async {
      await service.enrollInstallation(
        api,
        device['token'] as String,
        device['installation'] as String,
      );
      await admin.send(
        '/management',
        body: {
          'action': 'set_device',
          'store_id': store,
          'id': device['id'],
          'status': 'approved',
          'reason': 'Duyệt bản cài SQLite QA đã đăng ký',
        },
      );
      await api.secure.write(
        key: 'installation_id',
        value: device['installation'] as String,
      );
      service.onlineLogin = (username, password) =>
          api.login(username, password, store, service.deviceId);
      await service.login('admin', password);
    }

    await enroll(a, apiA, Map<String, dynamic>.from(context['a'] as Map));
    await enroll(b, apiB, Map<String, dynamic>.from(context['b'] as Map));
    var engineA = SyncEngine(a, apiA);
    final engineB = SyncEngine(b, apiB);
    engines.addAll([engineA, engineB]);
    Future<void> sync(
      SyncEngine engine, {
      SyncStatus status = SyncStatus.synced,
    }) async {
      engine.start();
      await engine.sync();
      await engine.pauseAndDrain();
      expect(engine.status, status, reason: engine.detail);
    }

    await sync(engineA);
    await sync(engineB);
    final sku = 'QA-${a.uuid.v7()}';
    await a.saveVariant(
      name: 'Áo QA cloud E2E',
      category: 'Áo sơ mi',
      gender: 'Unisex',
      level: 'Tiểu học',
      year: '2026–2027',
      size: 'M',
      color: 'Trắng',
      unit: 'cái',
      sku: sku,
      barcode: '',
      price: 100000,
      cost: 50000,
      threshold: 2,
    );
    final variant =
        (await a.catalog()).singleWhere((row) => row['sku'] == sku)['id']
            as String;
    await a.adjustStock(variant, 10, 'Nhập kho QA A');
    await sync(engineA);
    await sync(engineB);
    await b.adjustStock(variant, 4, 'Nhập kho QA B');
    await sync(engineB);
    await sync(engineA);
    gateA.offline = true;
    gateB.offline = true;
    final first = await a.sell(
      items: [CartItem(variant, 3)],
      discount: 0,
      received: 100000,
      method: 'cash',
      customerName: 'Phụ huynh QA offline',
    );
    final second = await b.sell(
      items: [CartItem(variant, 4)],
      discount: 0,
      received: 400000,
      method: 'bank',
    );
    expect(first.code, isNot(second.code));
    expect(first.code.endsWith('-001'), true);
    expect(second.code.endsWith('-001'), true);
    final beforeB = await dbB.rows('SELECT id FROM outbox ORDER BY id');
    await expectLater(
      b.sell(
        items: [CartItem(variant, 1)],
        discount: 0,
        received: 100000,
        method: 'cash',
      ),
      throwsA(isA<StateError>()),
    );
    expect(await dbB.rows('SELECT id FROM outbox ORDER BY id'), beforeB);
    await sync(engineA, status: SyncStatus.offline);
    gateA.offline = false;
    gateA.dropNextPushAck = true;
    // Restart only the engine to clear its real offline backoff, preserving the queue.
    final tokenA = apiA.token;
    final sessionA = a.session;
    await engineA.pauseAndDrain();
    engineA.dispose();
    engines.remove(engineA);
    gateA = _NetworkGate()..dropNextPushAck = true;
    apiA = CloudApi(origin, client: gateA)
      ..token = tokenA
      ..currentUserId = sessionA!.userId
      ..currentUsername = 'admin';
    engineA = SyncEngine(a, apiA);
    engines.add(engineA);
    final pendingA = await dbA.rows('SELECT id FROM outbox ORDER BY id');
    await sync(engineA, status: SyncStatus.offline);
    expect(gateA.droppedAcks, 1);
    expect(await dbA.rows('SELECT id FROM outbox ORDER BY id'), pendingA);
    final retryToken = apiA.token;
    await engineA.pauseAndDrain();
    engineA.dispose();
    engines.remove(engineA);
    await dbA.close();
    dbA = AppDatabase(NativeDatabase(fileA));
    a = LocalService(
      dbA,
      storeId: store,
      deviceId: context['a']['id'] as String,
    )..session = sessionA;
    gateA = _NetworkGate();
    apiA = CloudApi(origin, client: gateA)
      ..token = retryToken
      ..currentUserId = sessionA.userId
      ..currentUsername = 'admin';
    engineA = SyncEngine(a, apiA);
    engines.add(engineA);
    await sync(engineA);
    gateB.offline = false;
    await sync(engineB);
    await sync(engineA);
    final payment = await a.collectDebt(
      documentId: first.id,
      amount: 200000,
      method: 'bank',
      note: 'QA tất toán sau đồng bộ',
    );
    expect(
      await a.collectDebt(
        documentId: first.id,
        amount: 200000,
        method: 'bank',
        note: 'QA tất toán sau đồng bộ',
        commandId: payment,
      ),
      payment,
    );
    await sync(engineA);
    await sync(engineB);
    await dbA.execute('UPDATE sync_cursors SET server_seq=0 WHERE store_id=?', [
      store,
    ]);
    await sync(engineA);
    for (final db in [dbA, dbB]) {
      expect(await db.rows('SELECT id FROM outbox'), isEmpty);
      expect(
        (await db.rows(
          'SELECT quantity FROM stock_balances WHERE variant_id=?',
          [variant],
        )).single['quantity'],
        7,
      );
      expect(
        (await db.rows(
          'SELECT SUM(quantity) AS n FROM stock_movements WHERE variant_id=?',
          [variant],
        )).single['n'],
        7,
      );
      expect(
        (await db.rows(
          'SELECT SUM(amount) AS n FROM payments WHERE document_id IN (?,?)',
          [first.id, second.id],
        )).single['n'],
        700000,
      );
      expect(
        (await db.rows(
          'SELECT COUNT(*) AS n FROM payments WHERE document_id IN (?,?)',
          [first.id, second.id],
        )).single['n'],
        3,
      );
      expect(
        (await db.rows(
          'SELECT SUM(amount) AS n FROM receivable_entries WHERE document_id=?',
          [first.id],
        )).single['n'],
        0,
      );
      expect(
        (await db.rows(
          'SELECT COUNT(*) AS n FROM documents WHERE id IN (?,?)',
          [first.id, second.id],
        )).single['n'],
        2,
      );
      expect(
        (await db.rows('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rows('PRAGMA foreign_key_check'), isEmpty);
    }
    passed = true;
    stdout.writeln(
      'PASS real cloud: two SQLite files, offline codes, lost ACK/restart/replay, stock=7, receipts=700000, debt=0.',
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
