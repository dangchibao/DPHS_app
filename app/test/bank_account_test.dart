import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image/image.dart' as img;
import 'package:ngoc_thanh_pos/core/media/image_encoder.dart';
import 'package:ngoc_thanh_pos/core/auth/permissions.dart';
import 'package:ngoc_thanh_pos/features/settings/bank_account.dart';
import 'package:ngoc_thanh_pos/features/settings/bank_account_page.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const account = BankAccount(
    bank: 'Ngân hàng mẫu',
    number: '0123456789',
    holder: 'NGOC THANH',
  );
  test(
    'Cấu hình, audit và outbox nguyên tử; thu ngân xem nhưng không sửa',
    () async {
      final s = await salesFixture();
      addTearDown(s.db.close);
      expect(await s.bankAccount(), isNull);
      await s.db.execute(
        "CREATE TRIGGER fail_bank_outbox BEFORE INSERT ON outbox WHEN NEW.entity_type='bank_account' BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
      );
      await expectLater(
        s.saveBankAccount(account, 'Thêm tài khoản'),
        throwsA(anything),
      );
      expect(await s.db.rows('SELECT * FROM bank_accounts'), isEmpty);
      expect(
        await s.db.rows(
          "SELECT * FROM audit_logs WHERE action='BANK_ACCOUNT_SAVE'",
        ),
        isEmpty,
      );
      await s.db.execute('DROP TRIGGER fail_bank_outbox');
      await s.saveBankAccount(account, 'Thêm tài khoản');
      expect((await s.bankAccount())!.number, account.number);
      final queued = await s.db.rows(
        "SELECT payload FROM outbox WHERE entity_type='bank_account'",
      );
      expect(
        (jsonDecode(
          queued.single['payload'] as String,
        ) as List).single['table'],
        'bank_accounts',
      );
      s.session = LocalSession(
        userId: 'u1',
        name: 'Thu ngân',
        role: Role.cashier,
        storeId: s.storeId,
        deviceId: s.deviceId,
        expiresAt: DateTime.utc(2027),
      );
      expect((await s.bankAccount())!.holder, 'NGOC THANH');
      await expectLater(
        s.saveBankAccount(account, 'Thay đổi'),
        throwsStateError,
      );
    },
  );
  test(
    'Nén PNG/JPEG thật, giữ tỷ lệ và bỏ metadata; từ chối ảnh sai/quá lớn',
    () async {
      final source = img.Image(width: 1200, height: 600)
        ..textData = {'private-fixture': 'metadata-only'};
      img.fill(source, color: img.ColorRgb8(20, 80, 180));
      final encoded = await prepareImage(img.encodePng(source));
      final restored = img.decodeJpg(encoded)!;
      expect(restored.width, 1024);
      expect(restored.height, 512);
      expect(encoded.length, lessThanOrEqualTo(204800));
      expect(restored.textData, isNull);
      final tiny = img.Image(width: 100, height: 100);
      final qr = await prepareImage(img.encodePng(tiny), qr: true);
      expect(img.decodePng(qr)!.width, 100);
      expect(qr.length, lessThanOrEqualTo(65536));
      BankAccount(
        bank: account.bank,
        number: account.number,
        holder: account.holder,
        qr: qr,
      ).validate();
      await expectLater(
        prepareImage(Uint8List.fromList(utf8.encode('<svg/>'))),
        throwsArgumentError,
      );
      await expectLater(
        prepareImage(Uint8List(8 * 1024 * 1024 + 1)),
        throwsArgumentError,
      );
    },
  );
  testWidgets('Cấu hình mobile lưu thật và POS hiển thị thông tin ngân hàng', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = (await tester.runAsync(salesFixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BankAccountPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Ngân hàng'), account.bank);
    await tester.enterText(field('Số tài khoản'), account.number);
    await tester.enterText(field('Chủ tài khoản'), account.holder);
    await tester.enterText(
      field('Lý do thay đổi (bắt buộc)'),
      'Kiểm tra fixture',
    );
    await tester.ensureVisible(find.text('Lưu cấu hình cửa hàng'));
    await tester.tap(find.text('Lưu cấu hình cửa hàng'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(s.bankAccount))!.number, account.number);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BankTransferDetails(account: account)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('0123456789'), findsOneWidget);
    expect(find.text('NGOC THANH'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
