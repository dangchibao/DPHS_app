import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:ngoc_thanh_pos/core/export/xlsx_export.dart';

void main() {
  test(
    'XLSX thực, tiếng Việt, số nguyên, chuỗi bắt đầu = không thành công thức',
    () async {
      final bytes = buildXlsx(
        ['Sản phẩm', 'Số tiền', 'Ghi chú'],
        [
          ['Áo sơ mi trắng', 125000, '=SUM(1,2)'],
          ['Mũ & giày', 9007199254740991, '<Không có công thức>'],
        ],
        moneyColumns: {1},
      );
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final files = {
        for (final file in archive.files)
          file.name: utf8.decode(file.content as List<int>),
      };
      for (final xml in files.values) {
        expect(() => XmlDocument.parse(xml), returnsNormally);
      }
      final sheet = XmlDocument.parse(files['xl/worksheets/sheet1.xml']!);
      expect(sheet.findAllElements('f'), isEmpty);
      final cells = {
        for (final c in sheet.findAllElements('c')) c.getAttribute('r'): c,
      };
      expect(cells['B2']!.findElements('v').single.innerText, '125000');
      expect(cells['B3']!.getAttribute('t'), 'inlineStr');
      expect(
        cells['B3']!.findAllElements('t').single.innerText,
        '9007199254740991',
      );
      expect(cells['C2']!.findAllElements('t').single.innerText, '=SUM(1,2)');
      expect(
        cells['A2']!.findAllElements('t').single.innerText,
        'Áo sơ mi trắng',
      );
      final folder = Directory('../artifacts');
      await folder.create(recursive: true);
      await File('${folder.path}/qa-export.xlsx').writeAsBytes(bytes);
    },
  );
  test('Từ chối số lẻ trong cột tiền', () {
    expect(
      () => buildXlsx(
        ['Tiền'],
        [
          [1.5],
        ],
        moneyColumns: {0},
      ),
      throwsArgumentError,
    );
  });
}
