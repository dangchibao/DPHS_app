/// Tổng báo cáo có thể vượt 2^53; định dạng trực tiếp chữ số, không qua double.
String formatWholeVnd(BigInt value) {
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(end < 3 ? 0 : end - 3, end));
  }
  return '${value.isNegative ? '-' : ''}${groups.join('.')} đ';
}

/// Largest remainder allocation: số nguyên, tổng từng dòng luôn bằng số tiền cần chia.
List<int> allocateMoney(int amount, List<int> weights) {
  if (amount < 0 || weights.any((w) => w < 0)) {
    throw ArgumentError('Số tiền không hợp lệ.');
  }
  final sum = weights.fold(0, (a, b) => a + b);
  if (sum == 0) {
    if (amount != 0) throw ArgumentError('Không thể phân bổ.');
    return List.filled(weights.length, 0);
  }
  final total = BigInt.from(sum), value = BigInt.from(amount);
  final result = weights
      .map((w) => (value * BigInt.from(w) ~/ total).toInt())
      .toList();
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final diff = (value * BigInt.from(weights[b]) % total).compareTo(
        value * BigInt.from(weights[a]) % total,
      );
      return diff != 0 ? diff : a.compareTo(b);
    });
  final missing = amount - result.fold(0, (a, b) => a + b);
  for (var i = 0; i < missing; i++) {
    result[order[i]]++;
  }
  return result;
}
