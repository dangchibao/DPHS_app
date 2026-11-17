import 'dart:io';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/sizes/sizes_page.dart';
import 'package:ngoc_thanh_pos/features/sizes/size_service.dart';
import 'package:ngoc_thanh_pos/features/sizes/size_rule.dart';

import 'fixtures.dart';

void main() {
  testWidgets('Quản lý nhập bảng size bằng cm/kg từ giao diện', (tester) async {
    final s = (await tester.runAsync(salesFixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizesPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm bảng size'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    for (final entry in {
      'Tên bảng size': 'Bảng áo chính khóa',
      'Size': 'M',
      'Cao từ (cm)': '120',
      'Cao đến (cm)': '140',
      'Nặng từ (kg)': '20',
      'Nặng đến (kg)': '40',
    }.entries) {
      await tester.ensureVisible(field(entry.key));
      await tester.enterText(field(entry.key), entry.value);
    }
    await tester.tap(find.text('Lưu bảng size'));
    await tester.pumpAndSettle();
    final rules = (await tester.runAsync(s.sizeRules))!;
    expect(rules, hasLength(1));
    final band = SizeRule.parse(rules.single['config_json'] as String)
        .rows
        .single;
    expect(band['height_min'], 1200);
    expect(band['weight_max'], 40000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Mobile gợi ý cả hai size theo bảng cấu hình và không tràn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = (await tester.runAsync(salesFixture))!;
    addTearDown(() => tester.runAsync(s.db.close));
    final data = jsonDecode(
      File('../docs/test-vectors/size-suggestions.json').readAsStringSync(),
    ) as Map;
    await tester.runAsync(
      () => s.saveSizeRule(
        name: 'Bảng áo',
        rule: SizeRule.parse(jsonEncode(data['rows'])),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizesPage(service: s)),
      ),
    );
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Chiều cao (cm)'), '130');
    await tester.enterText(field('Cân nặng (kg)'), '30');
    await tester.ensureVisible(find.text('Gợi ý size'));
    await tester.tap(find.text('Gợi ý size'));
    await tester.pumpAndSettle();
    expect(find.byType(Chip), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
