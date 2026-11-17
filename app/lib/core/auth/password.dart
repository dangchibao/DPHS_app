import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

class Passwords {
  static String salt() {
    final random = Random.secure();
    return base64Encode(List.generate(16, (_) => random.nextInt(256)));
  }

  static Future<String> hash(String password, String salt) =>
      compute(_derive, [password, salt]);
  static String cloudSalt() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<String> cloudCredential(String password, String salt) =>
      compute(_deriveCloud, [password, salt]);
  static bool equal(String a, String b) {
    final aa = utf8.encode(a), bb = utf8.encode(b);
    var difference = aa.length ^ bb.length;
    for (var i = 0; i < aa.length; i++) {
      difference |= aa[i] ^ (i < bb.length ? bb[i] : 0);
    }
    return difference == 0;
  }
}

Future<String> _deriveCloud(List<String> values) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 600000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(values[0])),
        nonce: utf8.encode(values[1]),
      );
  return (await key.extractBytes())
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<String> _derive(List<String> values) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 600000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(values[0])),
        nonce: base64Decode(values[1]),
      );
  return base64Encode(await key.extractBytes());
}
