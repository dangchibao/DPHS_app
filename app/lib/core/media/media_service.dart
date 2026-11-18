import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../local_service.dart';
import '../auth/permissions.dart';

final _downloads = Expando<Map<String, Future<Uint8List?>>>();

extension ProductMediaService on LocalService {
  /// Called from the catalog transaction; the parent writes image_path, audit
  /// and catalog outbox in that same transaction. Cache bytes enter backups.
  Future<String> stageProductImage(Uint8List bytes) async {
    final actor = require(Permission.catalog);
    if (bytes.isEmpty || bytes.length > 204800) {
      throw ArgumentError('Ảnh sản phẩm tối đa 200KB sau nén.');
    }
    final info = img.JpegDecoder(maxPixels: 1048576).startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width > 1024 ||
        info.height > 1024) {
      throw ArgumentError('Ảnh sản phẩm phải là JPEG tối đa 1024×1024.');
    }
    final hash = sha256.convert(bytes).toString();
    await db.execute('INSERT OR IGNORE INTO media_cache VALUES(?,?,?)', [
      hash,
      bytes,
      now,
    ]);
    if ((await db.rows(
      'SELECT id FROM media_outbox WHERE store_id=? AND device_id=? AND hash=? AND user_id=?',
      [storeId, deviceId, hash, actor.userId],
    )).isEmpty) {
      await db.execute(
        'INSERT INTO media_outbox(id,store_id,device_id,user_id,hash,created_at) VALUES(?,?,?,?,?,?)',
        [uuid.v7(), storeId, deviceId, actor.userId, hash, now],
      );
    }
    return 'sha256:$hash';
  }

  Future<void> syncProductImages({required bool enabled}) async {
    if (!enabled || restoreBlocked) return;
    final engine = syncEngine;
    if (engine == null) return;
    final jobs = await db.rows(
      'SELECT * FROM media_outbox WHERE store_id=? AND device_id=? AND next_attempt_at<=? ORDER BY created_at,id LIMIT 1',
      [storeId, deviceId, clock().millisecondsSinceEpoch],
    );
    for (final job in jobs) {
      try {
        final bytes =
            (await db.rows('SELECT content FROM media_cache WHERE id=?', [
                  job['hash'],
                ])).single['content']
                as Uint8List;
        final token = await engine.api.syncTokenFor(
          job['user_id'] as String,
          storeId,
          deviceId,
        );
        if (token == null) {
          throw StateError(
            'Cần người thêm ảnh đăng nhập online lại để gửi ảnh.',
          );
        }
        final result = jsonDecode(
          utf8.decode(
            await engine.api.mediaBytes(
              job['hash'] as String,
              upload: bytes,
              mutationId: job['id'] as String,
              tokenOverride: token,
            ),
          ),
        ) as Map;
        if (result['id'] != job['id'] ||
            result['hash'] != job['hash'] ||
            result['ok'] != true) {
          throw StateError('Biên nhận ảnh không hợp lệ.');
        }
        await db.execute(
          'DELETE FROM media_outbox WHERE store_id=? AND device_id=? AND hash=?',
          [storeId, deviceId, job['hash']],
        );
      } catch (error) {
        final delay =
            15 * (1 << ((job['attempts'] as int).clamp(0, 8))) +
            Random().nextInt(16);
        await db.execute(
          'UPDATE media_outbox SET attempts=attempts+1,last_error=?,next_attempt_at=? WHERE store_id=? AND id=?',
          [
            error.toString().substring(
              0,
              error.toString().length.clamp(0, 500),
            ),
            clock()
                .add(Duration(seconds: delay.clamp(15, 3600)))
                .millisecondsSinceEpoch,
            storeId,
            job['id'],
          ],
        );
        // Optional image sync never makes the financial queue fail or replays a sale.
      }
    }
  }

  Future<Uint8List?> productImage(String? reference) async {
    final actor = session;
    if (actor == null ||
        !actor.expiresAt.isAfter(clock()) ||
        actor.storeId != storeId) {
      throw StateError('Vui lòng đăng nhập.');
    }
    if (reference == null ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(reference)) {
      return null;
    }
    final hash = reference.substring(7),
        cache = await db.rows('SELECT content FROM media_cache WHERE id=?', [
          hash,
        ]);
    if (cache.isNotEmpty) {
      final bytes = cache.single['content'] as Uint8List;
      if (sha256.convert(bytes).toString() != hash) {
        throw StateError('Checksum ảnh trong cache không khớp.');
      }
      return bytes;
    }
    final engine = syncEngine;
    if (engine?.mediaEnabled != true ||
        (await db.rows('SELECT id FROM media_objects WHERE id=?', [
          hash,
        ])).isEmpty) {
      return null;
    }
    final pending = _downloads[this] ??= <String, Future<Uint8List?>>{};
    if (pending.containsKey(hash)) return pending[hash];
    final work = () async {
      try {
        final bytes = await engine!.api.mediaBytes(hash);
        if (bytes.length > 204800 || sha256.convert(bytes).toString() != hash) {
          throw StateError('Checksum ảnh cloud không khớp.');
        }
        if (session?.userId != actor.userId ||
            session?.expiresAt.isAfter(clock()) != true) {
          throw StateError('Phiên đã thay đổi.');
        }
        await db.execute('INSERT OR IGNORE INTO media_cache VALUES(?,?,?)', [
          hash,
          bytes,
          now,
        ]);
        return bytes;
      } finally {
        pending.remove(hash);
      }
    }();
    pending[hash] = work;
    return work;
  }
}
