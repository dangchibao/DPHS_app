import 'dart:convert';

import '../pos/pricing.dart';

const measurementLabels = <String, String>{
  'chest': 'Ngực',
  'waist': 'Eo',
  'hips': 'Mông',
  'shirt_length': 'Dài áo',
  'trousers_length': 'Dài quần',
  'shoulder': 'Vai',
  'height': 'Chiều cao',
  'weight': 'Cân nặng',
};
const tailoringStatuses = ['Mới nhận', 'Đang may', 'Xong', 'Đã giao'];
const tailoringSteps = ['TAILOR_SEWING', 'TAILOR_READY', 'TAILOR_DELIVERED'];

int measurementInput(String text, String field) {
  final digits = field == 'weight' ? 3 : 1,
      value = text.trim().replaceAll(',', '.');
  if (!RegExp('^\\d+(\\.\\d{1,$digits})?\$').hasMatch(value)) {
    throw ArgumentError(
      'Nhập ${measurementLabels[field]} hợp lệ (${field == 'weight' ? 'kg' : 'cm'}).',
    );
  }
  final parts = value.split('.'), scale = field == 'weight' ? 1000 : 10;
  final result =
      BigInt.parse(parts[0]) * BigInt.from(scale) +
      (parts.length == 1
          ? BigInt.zero
          : BigInt.parse(parts[1].padRight(digits, '0')));
  if (result < BigInt.one || result > BigInt.from(1000000)) {
    throw ArgumentError('Số đo ngoài giới hạn.');
  }
  return result.toInt();
}

String measurementText(int value, String field) {
  final scale = field == 'weight' ? 1000 : 10,
      digits = field == 'weight' ? 3 : 1;
  final fraction = (value % scale)
      .toString()
      .padLeft(digits, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${value ~/ scale}${fraction.isEmpty ? '' : ',$fraction'}';
}

class TailoringRule {
  TailoringRule({
    required this.id,
    required this.version,
    required this.name,
    required this.config,
  }) {
    validate();
  }
  final String id, version, name;
  final Map<String, Object?> config;
  Map<String, Object?> get proof => {'id': id, 'version': version};
  static Map<String, Object?> defaults() => {
    'base_fee': 0,
    'rates': <String, Object?>{},
    'options': <String, Object?>{},
  };
  factory TailoringRule.fromRow(Map<String, Object?> row) => TailoringRule(
    id: row['id'] as String,
    version: row['lww_key'] as String,
    name: row['name'] as String,
    config: Map<String, Object?>.from(
      jsonDecode(row['config_json'] as String) as Map,
    ),
  );
  void validate() {
    Never bad() => throw ArgumentError('Cấu hình phụ thu may không hợp lệ.');
    if (id.isEmpty ||
        version.isEmpty ||
        name.trim().isEmpty ||
        name.length > 200 ||
        config.length != 3 ||
        !['base_fee', 'rates', 'options'].every(config.containsKey)) {
      bad();
    }
    void money(Object? value) {
      if (value is! int || value < 0 || value > maximumMoney) {
        bad();
      }
    }

    money(config['base_fee']);
    final rates = config['rates'], options = config['options'];
    if (rates is! Map || options is! Map || options.length > 20) {
      bad();
    }
    for (final entry in rates.entries) {
      final r = entry.value;
      if (!measurementLabels.containsKey(entry.key) ||
          r is! Map ||
          r.length != 3 ||
          !['threshold', 'step', 'amount'].every(r.containsKey)) {
        bad();
      }
      if (r['threshold'] is! int ||
          (r['threshold'] as int) < 0 ||
          (r['threshold'] as int) > 1000000 ||
          r['step'] is! int ||
          (r['step'] as int) < 1 ||
          (r['step'] as int) > 1000000) {
        bad();
      }
      money(r['amount']);
    }
    for (final entry in options.entries) {
      final o = entry.value;
      if (entry.key is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(entry.key as String) ||
          o is! Map ||
          o.length != 2 ||
          o['label'] is! String ||
          (o['label'] as String).trim().isEmpty ||
          (o['label'] as String).length > 200) {
        bad();
      }
      money(o['amount']);
    }
  }

  int fee(Map<String, int> measurements, List<String> selected) {
    if (measurements.length != 8 ||
        !measurementLabels.keys.every(measurements.containsKey) ||
        measurements.values.any((v) => v < 1 || v > 1000000)) {
      throw ArgumentError('Nhập đủ 8 số đo dương.');
    }
    final options = config['options'] as Map;
    if (selected.length > 20 ||
        selected.toSet().length != selected.length ||
        selected.any((k) => !options.containsKey(k))) {
      throw ArgumentError('Yêu cầu may đã chọn không hợp lệ.');
    }
    var amount = BigInt.from(config['base_fee'] as int);
    for (final entry in (config['rates'] as Map).entries) {
      final rate = entry.value as Map,
          excess = measurements[entry.key]! - (rate['threshold'] as int),
          step = rate['step'] as int;
      if (excess > 0) {
        amount +=
            ((BigInt.from(excess) + BigInt.from(step) - BigInt.one) ~/
                BigInt.from(step)) *
            BigInt.from(rate['amount'] as int);
      }
    }
    for (final key in selected) {
      amount += BigInt.from((options[key] as Map)['amount'] as int);
    }
    return checkedMoney(amount);
  }
}
