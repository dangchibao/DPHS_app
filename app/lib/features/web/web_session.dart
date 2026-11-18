import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/sync/cloud_api.dart';
import '../../core/auth/permissions.dart';

/// Không mở SQLite, không lưu token/lease hoặc tự đăng nhập lại khi mất mạng.
class WebSession extends ChangeNotifier {
  WebSession(this.api, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now {
    api.onUnauthorized = () =>
        invalidate('Phiên online hết hạn hoặc đã bị thu hồi.');
  }
  final CloudApi api;
  final DateTime Function() clock;
  Map<String, Object?>? user;
  String? storeId, deviceId, message;
  DateTime? expiresAt;
  Timer? _timer;
  bool _checking = false;
  bool get active =>
      user != null && expiresAt?.isAfter(clock()) == true && api.token != null;
  bool can(Permission permission) =>
      active &&
      permissionsByRole[Role.values.byName(user!['role'] as String)]!.contains(
        permission,
      );
  void accept(Map<String, Object?> response) {
    user = Map<String, Object?>.from(response['user'] as Map);
    storeId = response['store_id'] as String;
    deviceId = response['device_id'] as String;
    expiresAt = DateTime.parse(response['expires_at'] as String);
    message = null;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => verify());
    notifyListeners();
  }

  Future<void> verify() async {
    if (_checking || user == null) return;
    if (!active) {
      invalidate('Phiên online đã hết hạn.');
      return;
    }
    _checking = true;
    final expected = api.token;
    try {
      final actor = await api.send('/auth/me');
      if (api.token != expected) return;
      if (actor['device_kind'] != 'web' ||
          actor['user_id'] != user!['id'] ||
          actor['role'] != user!['role'] ||
          actor['store_id'] != storeId ||
          actor['device_id'] != deviceId) {
        invalidate('Quyền truy cập đã thay đổi. Vui lòng đăng nhập lại.');
      }
    } catch (_) {
      if (api.token == expected) {
        invalidate(
          'Không xác minh được phiên online. Kết nối mạng rồi đăng nhập lại.',
        );
      }
    } finally {
      _checking = false;
    }
  }

  void invalidate(String reason) {
    _timer?.cancel();
    api.token = null;
    api.currentUserId = null;
    api.currentUsername = null;
    user = null;
    expiresAt = null;
    message = reason;
    notifyListeners();
  }

  Future<void> logout() async {
    final token = api.token;
    invalidate('Đã đăng xuất.');
    if (token != null) {
      try {
        await api.send('/auth/logout', body: {}, tokenOverride: token);
      } catch (_) {
        /* Token RAM đã xóa; phiên server có thời hạn. */
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    api.onUnauthorized = null;
    super.dispose();
  }
}
