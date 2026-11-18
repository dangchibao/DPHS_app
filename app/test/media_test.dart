import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngoc_thanh_pos/core/media/media_service.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/core/sync/sync_engine.dart';
import 'package:ngoc_thanh_pos/features/catalog/catalog_service.dart';

import 'fixtures.dart';

class _Api extends CloudApi {
  _Api(http.Client client) : super('https://fixture.test', client: client);
  String? rejectedUser;
  @override
  Future<String?> syncTokenFor(
    String user,
    String store,
    String device,
  ) async => user == rejectedUser ? null : 'fixture-sync';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Người có quyền gửi lại đúng ảnh của người đã thu hồi, hoàn tất các intent trùng hash', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    final content = File('../docs/test-vectors/product-photo.jpg')
        .readAsBytesSync();
    await s.db.transaction(() => s.stageProductImage(content));
    await s.db.execute(
      "INSERT INTO users VALUES('u2','manager','Quản lý','hash','salt',1,0,'2026-11-15')",
    );
    s.session = LocalSession(
      userId: 'u2',
      name: 'Quản lý',
      role: Role.manager,
      storeId: s.storeId,
      deviceId: s.deviceId,
      expiresAt: DateTime.utc(2027),
    );
    await s.db.transaction(() => s.stageProductImage(content));
    expect((await s.db.rows('SELECT id FROM media_outbox')).length, 2);
    var calls = 0;
    final api = _Api(
      MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'ok': true,
            'id': request.headers['X-Mutation-ID'],
            'hash': request.url.path.split('/').last,
          }),
          200,
        );
      }),
    )..rejectedUser = 'u1';
    final engine = SyncEngine(s, api);
    s.syncEngine = engine;
    addTearDown(engine.dispose);
    addTearDown(api.close);
    await s.syncProductImages(enabled: true);
    expect((await s.db.rows('SELECT id FROM media_outbox')).length, 2);
    await s.syncProductImages(enabled: true);
    expect(calls, 1);
    expect(await s.db.rows('SELECT id FROM media_outbox'), isEmpty);
    expect(
      (await s.db.rows('SELECT content FROM media_cache')).single['content'],
      content,
    );
  });
  final bytes = File('../docs/test-vectors/product-photo.jpg')
      .readAsBytesSync();
  Future<void> save(LocalService s, {bool remove = false}) => s.saveVariant(
    existing: {'product_id': 'p1', 'id': 'v1'},
    name: 'Áo có ảnh',
    category: 'Áo sơ mi',
    gender: 'Unisex',
    level: 'Tiểu học',
    year: '2026–2027',
    size: 'M',
    color: 'Trắng',
    unit: 'cái',
    sku: 'SKU1',
    barcode: '',
    price: 100000,
    cost: 50000,
    threshold: 5,
    imageChanged: true,
    image: remove ? null : bytes,
  );
  test('Ảnh/cache/binary queue/catalog/audit nguyên tử; bỏ ảnh không xóa dữ liệu cache', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    await s.db.execute(
      "CREATE TRIGGER fail_media_queue BEFORE INSERT ON media_outbox BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
    );
    await expectLater(save(s), throwsA(anything));
    expect(await s.db.rows('SELECT * FROM media_cache'), isEmpty);
    expect(
      (await s.db.rows("SELECT image_path FROM products WHERE id='p1'"))
          .single['image_path'],
      isNull,
    );
    await s.db.execute('DROP TRIGGER fail_media_queue');
    await save(s);
    final reference =
        (await s.db.rows("SELECT image_path FROM products WHERE id='p1'"))
                .single['image_path']
            as String;
    expect(await s.productImage(reference), bytes);
    expect((await s.db.rows('SELECT * FROM media_outbox')).length, 1);
    final row = await s.db.rows(
      "SELECT payload FROM outbox WHERE entity_type='catalog'",
    );
    expect(row, isNotEmpty);
    expect(row.last['payload'].toString(), contains(reference));
    await save(s, remove: true);
    expect((await s.db.rows('SELECT * FROM media_cache')).length, 1);
  });
  test(
    'Ảnh chờ được giữ khi R2 tắt/lỗi, backoff có kiểm soát; ACK đúng mới xóa',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      await save(s);
      var fail = true, calls = 0;
      final api = _Api(
        MockClient((request) async {
          calls++;
          if (fail) {
            return http.Response(
              jsonEncode({'error': 'R2 bận', 'code': 'CLOUD_LIMIT'}),
              503,
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'id': request.headers['X-Mutation-ID'],
              'hash': request.url.path.split('/').last,
            }),
            200,
          );
        }),
      );
      final engine = SyncEngine(s, api);
      s.syncEngine = engine;
      addTearDown(engine.dispose);
      addTearDown(api.close);
      await s.syncProductImages(enabled: false);
      expect(calls, 0);
      await s.syncProductImages(enabled: true);
      expect(calls, 1);
      expect(
        (await s.db.rows('SELECT attempts FROM media_outbox'))
            .single['attempts'],
        1,
      );
      await s.syncProductImages(enabled: true);
      expect(calls, 1);
      fail = false;
      await s.db.execute('UPDATE media_outbox SET next_attempt_at=0');
      await s.syncProductImages(enabled: true);
      expect(calls, 2);
      expect(await s.db.rows('SELECT * FROM media_outbox'), isEmpty);
    },
  );
  test('Chỉ tải hash đã công bố; sai checksum không được ghi cache', () async {
    final s = await salesFixture();
    addTearDown(s.db.close);
    final hash = sha256.convert(bytes).toString();
    var corrupt = true, calls = 0;
    final api = _Api(
      MockClient((request) async {
        calls++;
        return http.Response.bytes(
          corrupt ? Uint8List.fromList([1, 2, 3]) : bytes,
          200,
        );
      }),
    );
    api.token = 'fixture-interactive';
    final engine = SyncEngine(s, api)..mediaEnabled = true;
    s.syncEngine = engine;
    addTearDown(engine.dispose);
    addTearDown(api.close);
    expect(await s.productImage('sha256:$hash'), isNull);
    expect(calls, 0);
    await s.db.execute('INSERT INTO media_objects VALUES(?,?,?,?)', [
      hash,
      'image/jpeg',
      bytes.length,
      s.now,
    ]);
    await expectLater(s.productImage('sha256:$hash'), throwsStateError);
    expect(await s.db.rows('SELECT * FROM media_cache'), isEmpty);
    corrupt = false;
    expect(await s.productImage('sha256:$hash'), bytes);
    expect(await s.productImage('sha256:$hash'), bytes);
    expect(calls, 2);
  });
}
