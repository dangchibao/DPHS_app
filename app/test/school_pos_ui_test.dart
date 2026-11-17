import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ngoc_thanh_pos/features/pos/pos_page.dart';
import 'package:ngoc_thanh_pos/features/schools/school_service.dart';

import 'fixtures.dart';

void main() {
  testWidgets(
    'Chọn học sinh trên POS mobile hiện đúng phụ huynh, đóng thanh toán không lỗi',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = await salesFixture();
      addTearDown(service.db.close);
      final school = await service.saveSchool(
        name: 'Tiểu học Ngọc Thanh',
        level: 'Tiểu học',
      );
      final schoolClass = await service.saveClass(
        schoolId: school,
        name: '2A',
        year: '2026–2027',
      );
      await service.saveStudent(
        classId: schoolClass,
        code: 'HS001',
        name: 'Nguyễn An',
        parentName: 'Phụ huynh An',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PosPage(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áo sơ mi').last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Giỏ hàng (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thanh toán · F9'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Tìm học sinh / đơn tập thể',
      );
      await tester.enterText(field, 'Nguyễn An');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('HS001').last);
      await tester.pumpAndSettle();
      expect(find.text('Phụ huynh An'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Quay lại'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
