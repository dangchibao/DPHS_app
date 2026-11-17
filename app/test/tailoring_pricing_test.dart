import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoc_thanh_pos/features/tailoring/tailoring_rule.dart';

void main() {
  final vectors = jsonDecode(
    File('../docs/test-vectors/tailoring-surcharge.json').readAsStringSync(),
  ) as List;
  for (final raw in vectors) {
    final v = raw as Map;
    test(v['name'] as String, () {
      int run() {
        final rule = TailoringRule(
          id: 'r1',
          version: 'v',
          name: 'Phụ thu',
          config: {
            'base_fee': v['base_fee'] ?? 10000,
            'rates': {
              'chest': {'threshold': 1000, 'step': 50, 'amount': 15000},
            },
            'options': {
              'rush': {'label': 'May gấp', 'amount': 20000},
            },
          },
        );
        final measurements = <String, int>{
          'chest': v['chest'] as int,
          'waist': 800,
          'hips': 1000,
          'shirt_length': 700,
          'trousers_length': 900,
          'shoulder': 450,
          'height': 1700,
          'weight': 70000,
        };
        if (v['omit'] != null) {
          measurements.remove(v['omit']);
        }
        return rule.fee(
          measurements,
          List<String>.from(v['options'] as List? ?? []),
        );
      }

      if (v['reject'] == true) {
        expect(run, throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())));
      } else {
        expect(run(), v['expected']);
      }
    });
  }
  test('Đổi cm/kg sang mm/gram chính xác không float', () {
    expect(measurementInput('100,5', 'chest'), 1005);
    expect(measurementInput('12.345', 'weight'), 12345);
    expect(measurementText(12345, 'weight'), '12,345');
    expect(measurementText(1000, 'chest'), '100');
    expect(() => measurementInput('10.55', 'chest'), throwsArgumentError);
    expect(() => measurementInput('1844674407370955162', 'chest'), throwsArgumentError);
  });
}
