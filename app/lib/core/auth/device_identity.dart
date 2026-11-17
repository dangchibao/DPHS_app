import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

Future<String> installationId() async {
  const storage = FlutterSecureStorage();
  var id = await storage.read(key: 'installation_id');
  if (id == null) {
    id = const Uuid().v7();
    await storage.write(key: 'installation_id', value: id);
  }
  return id;
}

Future<String> installationHash() async =>
    sha256.convert(utf8.encode(await installationId())).toString();
