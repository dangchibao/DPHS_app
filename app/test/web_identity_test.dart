import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/core/sync/cloud_api.dart';
import 'package:ngoc_thanh_pos/features/web/web_portal.dart';

class _LoginApi extends CloudApi {
  _LoginApi(super.url, {this.reject = false, this.release});
  final bool reject;
  final Completer<void>? release;
  String? store, device;
  int calls = 0;
  @override
  Future<Map<String, Object?>> loginWeb(
    String username,
    String password,
    String store,
    String device, {
    String? installation,
  }) async {
    this.store = store;
    this.device = device;
    calls++;
    if (release != null) await release!.future;
    if (reject) {
      throw const CloudError(401, 'INVALID_CREDENTIALS', 'Sai thông tin thử');
    }
    token = 'fixture-token';
    return {
      'token': token,
      'user': {'id': 'u1', 'name': 'Thu ngân', 'role': 'cashier'},
      'store_id': store,
      'device_id': device,
      'expires_at': DateTime.now()
          .add(const Duration(hours: 8))
          .toIso8601String(),
    };
  }
}

Finder field(String label) => find.widgetWithText(TextField, label);
const storeLabel = 'ID cửa hàng (tự điền sau đăng ký)';
const deviceLabel = 'ID trình duyệt đã được duyệt';
const endpoint = 'https://fixture.test';

Future<void> submit(WidgetTester tester) async {
  await tester.enterText(field('Mật khẩu'), 'fixture-password-only');
  await tester.scrollUntilVisible(
    find.text('Đăng nhập online'),
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Đăng nhập online'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Đóng màn hình khi đang đăng nhập không lưu ID hoặc giữ token trả về muộn',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final release = Completer<void>();
      final api = _LoginApi(endpoint, release: release);
      await tester.pumpWidget(
        MaterialApp(
          home: WebPortal(initialEndpoint: endpoint, apiFactory: (_) => api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field(storeLabel), 's1');
      await tester.enterText(field(deviceLabel), 'w1');
      await tester.enterText(field('Mật khẩu'), 'fixture-password-only');
      await tester.scrollUntilVisible(
        find.text('Đăng nhập online'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Đăng nhập online'));
      await tester.pump();
      expect(api.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      release.complete();
      await tester.pumpAndSettle();
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
      expect(api.token, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Đăng nhập trực tiếp lưu cặp ID, mở lại tự điền và vẫn cần mật khẩu',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final first = _LoginApi(endpoint);
      await tester.pumpWidget(
        MaterialApp(
          home: WebPortal(initialEndpoint: endpoint, apiFactory: (_) => first),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field(storeLabel), 's1');
      await tester.enterText(field(deviceLabel), 'w1');
      await submit(tester);
      expect(first.calls, 1);
      const storage = FlutterSecureStorage();
      final values = await storage.readAll();
      expect(values.keys, ['web_identity:$endpoint']);
      expect(jsonDecode(values.values.single), {
        'store_id': 's1',
        'device_id': 'w1',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      final second = _LoginApi(endpoint);
      await tester.pumpWidget(
        MaterialApp(
          home: WebPortal(initialEndpoint: endpoint, apiFactory: (_) => second),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field(storeLabel)).controller!.text,
        's1',
      );
      expect(
        tester.widget<TextField>(field(deviceLabel)).controller!.text,
        'w1',
      );
      expect(
        tester.widget<TextField>(field('Mật khẩu')).controller!.text,
        isEmpty,
      );
      expect(second.calls, 0);
      await submit(tester);
      expect(second.store, 's1');
      expect(second.device, 'w1');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Cấu hình đã lưu không ghi đè cặp ID người dùng vừa nhập', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'web_store:$endpoint': 'old-store',
      'web_device:$endpoint': 'old-device',
    });
    final api = _LoginApi(endpoint);
    await tester.pumpWidget(
      MaterialApp(
        home: WebPortal(initialEndpoint: '', apiFactory: (_) => api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(field('Địa chỉ API HTTPS'), endpoint);
    await tester.enterText(field(storeLabel), 'chosen-store');
    await tester.enterText(field(deviceLabel), 'chosen-device');
    await submit(tester);
    expect(api.store, 'chosen-store');
    expect(api.device, 'chosen-device');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Đọc cấu hình cũ, đăng nhập lỗi không lưu ID mới hoặc thông tin bí mật',
    (tester) async {
      final legacy = {
        'web_store:$endpoint': 's1',
        'web_device:$endpoint': 'w1',
      };
      FlutterSecureStorage.setMockInitialValues(legacy);
      final api = _LoginApi(endpoint, reject: true);
      await tester.pumpWidget(
        MaterialApp(
          home: WebPortal(initialEndpoint: endpoint, apiFactory: (_) => api),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field(storeLabel)).controller!.text,
        's1',
      );
      await tester.enterText(field(storeLabel), 'not-saved');
      await tester.enterText(field(deviceLabel), 'not-saved-device');
      await submit(tester);
      expect(await const FlutterSecureStorage().readAll(), legacy);
      expect(
        tester.widget<TextField>(field('Mật khẩu')).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
