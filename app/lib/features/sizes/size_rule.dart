import 'dart:convert';

class SizeRule {
  SizeRule(this.rows) {
    validate();
  }
  final List<Map<String, Object?>> rows;
  factory SizeRule.parse(String json) => SizeRule(
    (jsonDecode(json) as List)
        .map((r) => Map<String, Object?>.from(r as Map))
        .toList(),
  );
  void validate() {
    if (rows.isEmpty || rows.length > 50) {
      throw ArgumentError('Bảng size cần 1–50 dòng.');
    }
    final sizes = <String>{};
    for (final row in rows) {
      if (row.length != 5 ||
          !row.keys.toSet().containsAll([
            'size',
            'height_min',
            'height_max',
            'weight_min',
            'weight_max',
          ])) {
        throw ArgumentError('Cột bảng size không hợp lệ.');
      }
      final size = row['size'];
      if (size is! String ||
          size.trim().isEmpty ||
          size != size.trim() ||
          size.length > 30 ||
          !sizes.add(size)) {
        throw ArgumentError('Tên size phải khác nhau, tối đa 30 ký tự.');
      }
      for (final field in [
        'height_min',
        'height_max',
        'weight_min',
        'weight_max',
      ]) {
        final value = row[field];
        if (value is! int || value < 1 || value > 1000000) {
          throw ArgumentError('Khoảng chiều cao/cân nặng không hợp lệ.');
        }
      }
      if ((row['height_min'] as int) > (row['height_max'] as int) ||
          (row['weight_min'] as int) > (row['weight_max'] as int)) {
        throw ArgumentError('Giá trị từ phải nhỏ hơn hoặc bằng giá trị đến.');
      }
    }
  }

  List<String> suggest(int height, int weight) {
    if (height < 1 || weight < 1 || height > 1000000 || weight > 1000000) {
      throw ArgumentError('Chiều cao/cân nặng không hợp lệ.');
    }
    return [
      for (final r in rows)
        if (height >= (r['height_min'] as int) &&
            height <= (r['height_max'] as int) &&
            weight >= (r['weight_min'] as int) &&
            weight <= (r['weight_max'] as int))
          r['size'] as String,
    ];
  }
}
