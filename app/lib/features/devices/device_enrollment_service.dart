import 'package:crypto/crypto.dart';

import 'dart:convert';

import '../../core/local_service.dart';
import '../../core/sync/cloud_api.dart';

extension DeviceEnrollment on LocalService {
  Future<void> enrollInstallation(
    CloudApi api,
    String token,
    String installation,
  ) async {
    if (await initialized ||
        (await db.rows('SELECT id FROM outbox LIMIT 1')).isNotEmpty) {
      throw StateError(
        'Chỉ đăng ký trên bản cài chưa có dữ liệu. Không thay danh tính máy đang dùng.',
      );
    }
    final response = await api.send(
      '/devices/enroll',
      authenticated: false,
      body: {'token': token.trim(), 'installation_id': installation},
    );
    final store = Map<String, Object?>.from(response['store'] as Map),
        device = Map<String, Object?>.from(response['device'] as Map);
    if (device['store_id'] != store['id'] ||
        !['pending', 'approved'].contains(device['status']) ||
        store['active'] != 1) {
      throw StateError('Thông tin thiết bị không hợp lệ.');
    }
    await db.transaction(() async {
      if (await initialized) throw StateError('Bản cài đã được khởi tạo.');
      await db.execute('INSERT INTO stores VALUES (?,?,?,?,?)', [
        store['id'],
        store['code'],
        store['name'],
        store['active'],
        store['created_at'],
      ]);
      await db.execute(
        'INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES (?,?,?,?,?,?)',
        [
          device['id'],
          device['store_id'],
          device['code'],
          device['name'],
          device['status'],
          device['created_at'],
        ],
      );
      for (final entry in <String, String>{
        'enrolled': '1',
        'identity_store': store['id'] as String,
        'identity_device': device['id'] as String,
        'cloud_url': api.baseUrl,
        'installation_hash': sha256
            .convert(utf8.encode(installation))
            .toString(),
      }.entries) {
        await db.execute(
          'INSERT INTO local_settings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          [entry.key, entry.value],
        );
      }
    });
  }
}
