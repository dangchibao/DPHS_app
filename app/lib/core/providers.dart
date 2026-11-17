import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import 'package:http/http.dart' as http;

import 'bootstrap_environment.dart';
import 'app_version.dart';
import 'database/open_database.dart';
import 'local_service.dart';
import 'sync/cloud_api.dart';
import 'sync/sync_engine.dart';
import 'auth/device_identity.dart' as identity;
import 'backup/backup_service.dart';

final localServiceProvider = FutureProvider<LocalService>((ref) async {
  final db = await openAppDatabase();
  ref.onDispose(() {
    db.close();
  });
  final settings = {
    for (final r in await db.rows(
      "SELECT key,value FROM local_settings WHERE key IN ('identity_store','identity_device','cloud_url','enrolled')",
    ))
      r['key'] as String: r['value'] as String,
  };
  final service = LocalService(
    db,
    storeId: settings['identity_store'] ?? LocalService.defaultStoreId,
    deviceId: settings['identity_device'] ?? LocalService.defaultDeviceId,
  );
  final api = CloudApi(settings['cloud_url'] ?? apiBaseUrl);
  final engine = SyncEngine(service, api);
  service.syncEngine = engine;
  service.onQueue = engine.schedule;
  service.onlineLogin = (username, password) async {
    try {
      return await api.login(
        username,
        password,
        service.storeId,
        service.deviceId,
      );
    } on CloudError catch (e) {
      if (e.status >= 400 && e.status < 500 && e.status != 429) rethrow;
      return null;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    }
  };
  service.onlineStaff = api.saveStaff;
  service.onlinePassword = api.changePassword;
  ref.onDispose(engine.dispose);
  final password = bootstrapPassword;
  if (settings['enrolled'] != '1' && password != null && password.isNotEmpty) {
    try {
      await api.bootstrap(password).timeout(const Duration(seconds: 15));
    } catch (_) {
      /* API có thể đã provision hoặc chưa mở. */
    }
  }
  if (!await service.initialized && password != null && password.isNotEmpty) {
    await service.bootstrap(password);
  }
  service.installationHash = await identity.installationHash();
  if (await service.initialized) {
    final hashes = await db.rows(
      "SELECT value FROM local_settings WHERE key='installation_hash'",
    );
    if (hashes.isEmpty) {
      await db.execute(
        "INSERT INTO local_settings VALUES ('installation_hash',?)",
        [service.installationHash],
      );
    } else if (hashes.single['value'] != service.installationHash) {
      await db.execute(
        "INSERT INTO local_settings VALUES ('restore_blocked','1') ON CONFLICT(key) DO UPDATE SET value='1'",
      );
      await db.execute(
        "INSERT INTO local_settings VALUES ('restore_reason','identity') ON CONFLICT(key) DO UPDATE SET value='identity'",
      );
    }
    service.restoreBlocked = (await db.rows(
      "SELECT value FROM local_settings WHERE key='restore_blocked' AND value='1'",
    )).isNotEmpty;
  }
  service.backup = BackupService(service);
  service.backupScheduler = BackupScheduler(service, service.backup!)..start();
  ref.onDispose(service.backupScheduler!.dispose);
  await db.execute(
    "INSERT INTO local_settings VALUES ('last_app_version',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
    [appVersion],
  );
  return service;
});
