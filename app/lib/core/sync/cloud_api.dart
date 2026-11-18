import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../auth/device_identity.dart';
import '../auth/password.dart';
import '../database/database.dart';

class CloudError implements Exception {
  const CloudError(this.status, this.code, this.message);
  final int status;
  final String code, message;
  @override
  String toString() => message;
}

class CloudApi {
  CloudApi(String baseUrl, {http.Client? client})
    : baseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
      client = client ?? http.Client();
  final String baseUrl;
  final http.Client client;
  final secure = const FlutterSecureStorage();
  String? token;
  String? currentUserId;
  String? currentUsername;
  VoidCallback? onUnauthorized;
  ({String username, String salt, String proof, String store, String device})?
  _pendingLogin;
  bool get hasPendingLogin => _pendingLogin != null;
  void cancelPendingLogin() {
    _pendingLogin = null;
  }

  final _syncTokens = <String, String>{};
  Future<String?> syncTokenFor(String user, String store, String device) async {
    final key = 'sync:$store:$device:$user';
    return _syncTokens[key] ?? await secure.read(key: key);
  }

  Future<Map<String, Object?>> send(
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
    String? tokenOverride,
  }) async {
    final uri = cloudEndpoint(
      baseUrl,
      path,
      allowDevelopmentHttp: !kReleaseMode,
    );
    final headers = {
      'Content-Type': 'application/json',
      'X-Client-Schema': '${AppDatabase.currentSchemaVersion}',
      if (authenticated && (tokenOverride ?? token) != null)
        'Authorization': 'Bearer ${tokenOverride ?? token}',
    };
    final response =
        await (body == null
                ? client.get(uri, headers: headers)
                : client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 15));
    Map<String, Object?> result;
    try {
      result = Map<String, Object?>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      if (response.statusCode >= 400) {
        if (RegExp(
          r'\b1027\b|exceeded free tier daily request limit',
          caseSensitive: false,
        ).hasMatch(response.body)) {
          throw CloudError(
            response.statusCode,
            'CLOUD_LIMIT',
            'Cloud đạt giới hạn ngày. Giao dịch được giữ trên máy và sẽ thử lại sau 07:00 giờ Việt Nam.',
          );
        }
        if (RegExp(
          r'\b1102\b|Worker exceeded resource limits',
          caseSensitive: false,
        ).hasMatch(response.body)) {
          throw CloudError(
            response.statusCode,
            'CLOUD_CPU_LIMIT',
            'Cloud đạt giới hạn xử lý. Giao dịch vẫn được giữ trên máy.',
          );
        }
      }
      throw CloudError(
        response.statusCode,
        'INVALID_RESPONSE',
        'Cloud tạm thời không trả dữ liệu hợp lệ.',
      );
    }
    if (response.statusCode >= 400) {
      if (authenticated && response.statusCode == 401) onUnauthorized?.call();
      throw CloudError(
        response.statusCode,
        result['code'] as String? ?? 'HTTP_ERROR',
        result['error'] as String? ?? 'Cloud tạm thời không khả dụng.',
      );
    }
    return result;
  }

  String _saltKey(String username) => 'cloud_salt:$baseUrl:$username';
  Future<Uint8List> mediaBytes(
    String hash, {
    Uint8List? upload,
    String? mutationId,
    String? tokenOverride,
  }) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw ArgumentError('Mã ảnh không hợp lệ.');
    }
    final request = http.Request(
      upload == null ? 'GET' : 'PUT',
      cloudEndpoint(
        baseUrl,
        '/media/$hash',
        allowDevelopmentHttp: !kReleaseMode,
      ),
    );
    request.headers.addAll({
      'Authorization': 'Bearer ${tokenOverride ?? token}',
      'X-Client-Schema': '${AppDatabase.currentSchemaVersion}',
      if (upload != null) 'Content-Type': 'image/jpeg',
      'X-Mutation-ID': ?mutationId,
    });
    if (upload != null) {
      if (upload.length > 204800) throw ArgumentError('Ảnh vượt 200KB.');
      request.bodyBytes = upload;
    }
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 20));
    final data = BytesBuilder(copy: false);
    await for (final part in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (data.length + part.length > 262144) {
        throw StateError('Cloud trả ảnh quá lớn.');
      }
      data.add(part);
    }
    final bytes = data.takeBytes();
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) onUnauthorized?.call();
      Map<String, Object?> details = {};
      try {
        details = Map<String, Object?>.from(
          jsonDecode(utf8.decode(bytes)) as Map,
        );
      } catch (_) {
        /* Không phải JSON khi cloud vượt hạn mức. */
      }
      throw CloudError(
        response.statusCode,
        details['code'] as String? ?? 'MEDIA_HTTP',
        details['error'] as String? ??
            'Không đồng bộ được ảnh. Ảnh vẫn lưu trên máy.',
      );
    }
    return bytes;
  }

  Future<Uint8List> archiveBytes(String id, {Uint8List? upload}) async {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw ArgumentError('ID file không hợp lệ.');
    }
    if (upload != null && upload.length > 194000) {
      throw ArgumentError('File quá lớn.');
    }
    final request = http.Request(
      upload == null ? 'GET' : 'PUT',
      cloudEndpoint(
        baseUrl,
        '/audit/archives/$id',
        allowDevelopmentHttp: !kReleaseMode,
      ),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'X-Client-Schema': '${AppDatabase.currentSchemaVersion}',
      if (upload != null) 'Content-Type': 'application/gzip',
    });
    if (upload != null) request.bodyBytes = upload;
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 20));
    final bytes = BytesBuilder(copy: false);
    await for (final part in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + part.length > 194000) {
        throw StateError('File trả về quá lớn.');
      }
      bytes.add(part);
    }
    final data = bytes.takeBytes();
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) onUnauthorized?.call();
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      } catch (_) {
        /* Lỗi proxy/quota có thể không phải JSON. */
      }
      throw CloudError(
        response.statusCode,
        error['code'] as String? ?? 'ARCHIVE_HTTP',
        error['error'] as String? ??
            'Không đọc/lưu được kho nhật ký. Log vẫn được giữ nếu chưa chốt.',
      );
    }
    if (upload != null) {
      final ack = jsonDecode(utf8.decode(data)) as Map;
      if (ack['id'] != id || ack['verified'] != true) {
        throw StateError('Cloud chưa xác nhận file.');
      }
    }
    return data;
  }

  /// Phiên Web chỉ giữ token trong RAM; không có sync token hoặc lease offline.
  Future<Map<String, Object?>> loginWeb(
    String username,
    String password,
    String store,
    String device, {
    String? installation,
  }) async {
    final challenge = await send(
      '/auth/challenge',
      body: {'username': username},
      authenticated: false,
    );
    final response = await send(
      '/auth/web/login',
      authenticated: false,
      body: {
        'username': username,
        'credential': await Passwords.cloudCredential(
          password,
          _challengeSalt(challenge),
        ),
        'store_id': store,
        'device_id': device,
        'installation_id': installation ?? await installationId(),
      },
    );
    if (response.containsKey('sync_token')) {
      throw StateError('Phiên Web không được cấp quyền đồng bộ offline.');
    }
    token = response['token'] as String;
    currentUserId = (response['user'] as Map)['id'] as String;
    currentUsername = username;
    return response;
  }

  String _challengeSalt(Map<String, Object?> challenge) {
    final salt = challenge['salt'];
    if (challenge['algorithm'] != 'PBKDF2-SHA256' ||
        challenge['iterations'] != 600000 ||
        salt is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(salt)) {
      throw const CloudError(
        409,
        'AUTH_PROTOCOL',
        'Phiên bản xác thực cloud không tương thích.',
      );
    }
    return salt;
  }

  Future<Map<String, Object?>> _submitLogin(
    String username,
    String salt,
    String proof,
    String store,
    String device,
  ) async {
    final response = await send(
      '/auth/login',
      body: {
        'username': username,
        'credential': proof,
        'store_id': store,
        'device_id': device,
        'installation_id': await installationId(),
      },
      authenticated: false,
    );
    token = response['token'] as String;
    currentUserId = (response['user'] as Map)['id'] as String;
    currentUsername = username;
    final sync = response['sync_token'] as String,
        key = 'sync:$store:$device:$currentUserId';
    _syncTokens[key] = sync;
    await secure.write(key: key, value: sync);
    await secure.write(key: 'cloud_token', value: token);
    await secure.write(key: _saltKey(username), value: salt);
    _pendingLogin = null;
    return response;
  }

  Future<Map<String, Object?>> login(
    String username,
    String password,
    String store,
    String device,
  ) async {
    _pendingLogin = null;
    final cachedSalt = await secure.read(key: _saltKey(username));
    var changed = false;
    try {
      final challenge = await send(
        '/auth/challenge',
        body: {'username': username},
        authenticated: false,
      );
      final salt = _challengeSalt(challenge);
      changed = cachedSalt != null && cachedSalt != salt;
      final proof = await Passwords.cloudCredential(password, salt);
      _pendingLogin = (
        username: username,
        salt: salt,
        proof: proof,
        store: store,
        device: device,
      );
      return await _submitLogin(username, salt, proof, store, device);
    } catch (error) {
      if (error is CloudError &&
          error.status >= 400 &&
          error.status < 500 &&
          error.status != 429) {
        _pendingLogin = null;
        if (error.status == 401 && changed) {
          throw const CloudError(
            401,
            'CREDENTIAL_CHANGED',
            'Thông tin đăng nhập đã thay đổi. Cần xác thực online lại.',
          );
        }
      } else if (_pendingLogin == null && cachedSalt != null) {
        _pendingLogin = (
          username: username,
          salt: cachedSalt,
          proof: await Passwords.cloudCredential(password, cachedSalt),
          store: store,
          device: device,
        );
      }
      rethrow;
    }
  }

  Future<Map<String, Object?>?> reconnect() async {
    final pending = _pendingLogin;
    if (pending == null) {
      return null;
    }
    try {
      final challenge = await send(
        '/auth/challenge',
        body: {'username': pending.username},
        authenticated: false,
      );
      if (_challengeSalt(challenge) != pending.salt) {
        throw const CloudError(
          401,
          'CREDENTIAL_CHANGED',
          'Mật khẩu hoặc tài khoản đã thay đổi. Vui lòng đăng nhập lại.',
        );
      }
      return await _submitLogin(
        pending.username,
        pending.salt,
        pending.proof,
        pending.store,
        pending.device,
      );
    } on CloudError catch (error) {
      if (error.status >= 400 && error.status < 500 && error.status != 429) {
        _pendingLogin = null;
      }
      rethrow;
    }
  }

  Future<Map<String, Object?>> bootstrap(String password) async {
    final salt = Passwords.cloudSalt();
    return send(
      '/auth/bootstrap',
      body: {
        'password': password,
        'salt': salt,
        'credential': await Passwords.cloudCredential(password, salt),
      },
      authenticated: false,
    );
  }

  Future<Map<String, Object?>> saveStaff(Map<String, Object?> input) async {
    final body = Map<String, Object?>.from(input);
    body.putIfAbsent('id', () => const Uuid().v7());
    body.putIfAbsent('change_id', () => const Uuid().v7());
    final password = body.remove('password') as String?;
    if (password != null) {
      final salt = Passwords.cloudSalt();
      body['salt'] = salt;
      body['credential'] = await Passwords.cloudCredential(password, salt);
    }
    return send('/staff', body: body);
  }

  Future<Map<String, Object?>> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    if (currentUsername == null) {
      throw const CloudError(
        401,
        'UNAUTHENTICATED',
        'Cần đăng nhập online lại.',
      );
    }
    final challenge = await send(
      '/auth/challenge',
      body: {'username': currentUsername},
      authenticated: false,
    );
    final salt = Passwords.cloudSalt();
    return send(
      '/auth/password',
      body: {
        'old_credential': await Passwords.cloudCredential(
          oldPassword,
          challenge['salt'] as String,
        ),
        'salt': salt,
        'credential': await Passwords.cloudCredential(newPassword, salt),
      },
    );
  }

  Future<void> logout() async {
    _pendingLogin = null;
    try {
      if (token != null) await send('/auth/logout', body: {});
    } catch (_) {
      /* Local logout vẫn xóa token. */
    }
    token = null;
    currentUserId = null;
    currentUsername = null;
    await secure.delete(key: 'cloud_token');
  }

  void close() => client.close();
}

Uri cloudEndpoint(
  String baseUrl,
  String path, {
  bool allowDevelopmentHttp = false,
}) {
  final base = Uri.tryParse(baseUrl);
  if (base == null ||
      !base.hasAuthority ||
      !['https', 'http'].contains(base.scheme) ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment ||
      !path.startsWith('/')) {
    throw const CloudError(
      400,
      'API_CONFIGURATION',
      'Địa chỉ API không hợp lệ.',
    );
  }
  if (base.scheme != 'https' &&
      !allowDevelopmentHttp &&
      !['localhost', '127.0.0.1', '::1', '10.0.2.2'].contains(base.host)) {
    throw const CloudError(
      400,
      'HTTPS_REQUIRED',
      'API trên Internet cần HTTPS để bảo vệ thông tin đăng nhập.',
    );
  }
  return Uri.parse('$baseUrl$path');
}
