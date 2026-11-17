import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const _main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _rels =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
String _clean(Object? value) => '$value'.runes
    .where(
      (c) =>
          c == 9 ||
          c == 10 ||
          c == 13 ||
          c >= 32 && c <= 0xd7ff ||
          c >= 0xe000 && c <= 0xfffd ||
          c >= 0x10000 && c <= 0x10ffff,
    )
    .map(String.fromCharCode)
    .join();
String _column(int index) {
  var n = index + 1, text = '';
  while (n > 0) {
    n--;
    text = String.fromCharCode(65 + n % 26) + text;
    n ~/= 26;
  }
  return text;
}

/// XLSX Open XML, inline strings (không thực thi công thức nhập từ dữ liệu).
/// Nguồn: learn.microsoft.com/en-us/office/open-xml/spreadsheet/structure-of-a-spreadsheetml-document
Uint8List buildXlsx(
  List<String> headers,
  List<List<Object?>> rows, {
  String sheetName = 'Báo cáo',
  Set<int> moneyColumns = const {},
}) {
  if (headers.isEmpty ||
      headers.length > 16384 ||
      rows.length >= 1048576 ||
      rows.any((row) => row.length > headers.length)) {
    throw ArgumentError('Bảng xuất vượt giới hạn Excel hoặc không khớp cột.');
  }
  final name = sheetName.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (name.isEmpty || name.length > 31) {
    throw ArgumentError('Tên trang tính phải dài 1–31 ký tự.');
  }
  final archive = Archive();
  final widths = List.generate(headers.length, (col) {
    var width = headers[col].length + 6;
    for (final row in rows) {
      if (col >= row.length || row[col] == null) continue;
      var length = row[col].toString().length + 2;
      if (moneyColumns.contains(col) && row[col] is int) {
        final digits = (row[col] as int).abs().toString().length;
        length += ((digits - 1) ~/ 3) + 2;
      }
      if (length > width) width = length;
    }
    return width.clamp(14, 50);
  });
  void add(String path, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    '[Content_Types].xml',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''',
  );
  add(
    '_rels/.rels',
    '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="$_rels/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
  );
  final workbook = XmlBuilder()
    ..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  workbook.element(
    'workbook',
    attributes: {'xmlns': _main, 'xmlns:r': _rels},
    nest: () {
      workbook.element(
        'bookViews',
        nest: () {
          workbook.element('workbookView');
        },
      );
      workbook.element(
        'sheets',
        nest: () {
          workbook.element(
            'sheet',
            attributes: {'name': name, 'sheetId': '1', 'r:id': 'rId1'},
          );
        },
      );
    },
  );
  add('xl/workbook.xml', workbook.buildDocument().toXmlString());
  add(
    'xl/_rels/workbook.xml.rels',
    '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="$_rels/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="$_rels/styles" Target="styles.xml"/></Relationships>''',
  );
  add(
    'xl/styles.xml',
    '''<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="$_main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0&quot; ₫&quot;"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1763C0"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''',
  );
  final sheet = XmlBuilder()
    ..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  sheet.element(
    'worksheet',
    attributes: {'xmlns': _main},
    nest: () {
      sheet.element(
        'dimension',
        attributes: {
          'ref': 'A1:${_column(headers.length - 1)}${rows.length + 1}',
        },
      );
      sheet.element(
        'sheetViews',
        nest: () {
          sheet.element(
            'sheetView',
            attributes: {'workbookViewId': '0', 'showGridLines': '0'},
            nest: () {
              sheet.element(
                'pane',
                attributes: {
                  'ySplit': '1',
                  'topLeftCell': 'A2',
                  'activePane': 'bottomLeft',
                  'state': 'frozen',
                },
              );
            },
          );
        },
      );
      sheet.element('sheetFormatPr', attributes: {'defaultRowHeight': '18'});
      sheet.element(
        'cols',
        nest: () {
          for (var col = 0; col < headers.length; col++) {
            sheet.element(
              'col',
              attributes: {
                'min': '${col + 1}',
                'max': '${col + 1}',
                'width': '${widths[col]}',
                'customWidth': '1',
              },
            );
          }
        },
      );
      sheet.element(
        'sheetData',
        nest: () {
          for (var i = 0; i <= rows.length; i++) {
            final data = i == 0 ? headers : rows[i - 1];
            sheet.element(
              'row',
              attributes: {
                'r': '${i + 1}',
                if (i == 0) 'ht': '24',
                if (i == 0) 'customHeight': '1',
              },
              nest: () {
                for (var col = 0; col < data.length; col++) {
                  final value = data[col];
                  if (value == null) continue;
                  if (moneyColumns.contains(col) &&
                      i > 0 &&
                      value is num &&
                      value is! int) {
                    throw ArgumentError('Tiền xuất Excel phải là số nguyên.');
                  }
                  final numeric =
                      value is num &&
                      value.isFinite &&
                      value.abs() < 1000000000000000;
                  sheet.element(
                    'c',
                    attributes: {
                      'r': '${_column(col)}${i + 1}',
                      's': i == 0
                          ? '1'
                          : moneyColumns.contains(col) && numeric
                          ? '2'
                          : '0',
                      if (!numeric) 't': 'inlineStr',
                    },
                    nest: () {
                      if (numeric) {
                        sheet.element('v', nest: value.toString());
                      } else {
                        sheet.element(
                          'is',
                          nest: () {
                            sheet.element(
                              't',
                              attributes: {'xml:space': 'preserve'},
                              nest: _clean(value),
                            );
                          },
                        );
                      }
                    },
                  );
                }
              },
            );
          }
        },
      );
      sheet.element(
        'autoFilter',
        attributes: {
          'ref': 'A1:${_column(headers.length - 1)}${rows.length + 1}',
        },
      );
    },
  );
  add('xl/worksheets/sheet1.xml', sheet.buildDocument().toXmlString());
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
