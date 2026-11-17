import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:drift/native.dart';
import 'package:ngoc_thanh_pos/core/database/database.dart';
import 'package:ngoc_thanh_pos/core/local_service.dart';
import 'package:ngoc_thanh_pos/features/auth/login_page.dart';

void main() {
  testWidgets('Màn khởi tạo tiếng Việt, có tài khoản và mật khẩu', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(service: LocalService(db), onLogin: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tài khoản'), findsOneWidget);
    expect(find.text('Khởi tạo và thử nghiệm'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await db.close();
  });
}
