/// Một đơn vị công là nửa ngày. Tất cả phép nhân/chia tiền dùng BigInt.
const _maximumPayrollMoney = 9007199254740991;

int _integer(Object? value, int minimum, [int maximum = _maximumPayrollMoney]) {
  if (value is! int || value < minimum || value > maximum) {
    throw ArgumentError('Cấu hình hoặc dữ liệu tính lương không hợp lệ.');
  }
  return value;
}

Map<String, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    throw ArgumentError('Cấu hình tính lương thiếu hoặc thừa trường.');
  }
  return Map<String, Object?>.from(value);
}

class CompensationRule {
  CompensationRule._(
    this.baseSalary,
    this.standardDays,
    this.commissionBps,
    this.bonusTiers,
  );
  final int baseSalary, standardDays, commissionBps;
  final List<({int threshold, int amount})> bonusTiers;

  factory CompensationRule.fromJson(Object? value) {
    final row = _object(value, {
      'base_salary',
      'standard_days',
      'commission_bps',
      'bonus_tiers',
    });
    final tiers = row['bonus_tiers'];
    if (tiers is! List || tiers.length > 20) {
      throw ArgumentError('Tối đa 20 bậc thưởng.');
    }
    var previous = -1;
    final parsed = <({int threshold, int amount})>[];
    for (final value in tiers) {
      final tier = _object(value, {'threshold', 'amount'}),
          threshold = _integer(tier['threshold'], 0),
          amount = _integer(tier['amount'], 0);
      if (threshold <= previous) {
        throw ArgumentError('Ngưỡng thưởng phải tăng dần, không trùng.');
      }
      previous = threshold;
      parsed.add((threshold: threshold, amount: amount));
    }
    return CompensationRule._(
      _integer(row['base_salary'], 0),
      _integer(row['standard_days'], 1, 31),
      _integer(row['commission_bps'], 0, 10000),
      List.unmodifiable(parsed),
    );
  }
  Map<String, Object?> toJson() => {
    'base_salary': baseSalary,
    'standard_days': standardDays,
    'commission_bps': commissionBps,
    'bonus_tiers': [
      for (final t in bonusTiers)
        {'threshold': t.threshold, 'amount': t.amount},
    ],
  };
}

Map<String, Object?> calculatePayroll({
  required CompensationRule rule,
  required int attendanceUnits,
  required int netSales,
}) {
  _integer(attendanceUnits, 0, 62);
  _integer(netSales, -_maximumPayrollMoney);
  final standardUnits = rule.standardDays * 2,
      paidUnits = attendanceUnits > standardUnits
          ? standardUnits
          : attendanceUnits,
      eligibleSales = netSales < 0 ? 0 : netSales;
  int? tierThreshold;
  var bonus = 0;
  for (final tier in rule.bonusTiers) {
    if (eligibleSales >= tier.threshold) {
      tierThreshold = tier.threshold;
      bonus = tier.amount;
    }
  }
  final base =
          BigInt.from(rule.baseSalary) *
          BigInt.from(paidUnits) ~/
          BigInt.from(standardUnits),
      commission =
          BigInt.from(eligibleSales) *
          BigInt.from(rule.commissionBps) ~/
          BigInt.from(10000),
      total = base + commission + BigInt.from(bonus);
  if (total > BigInt.from(_maximumPayrollMoney)) {
    throw ArgumentError('Tổng lương vượt giới hạn số nguyên VND an toàn.');
  }
  return {
    'attendance_units': attendanceUnits,
    'paid_units': paidUnits,
    'standard_units': standardUnits,
    'net_sales': netSales,
    'eligible_sales': eligibleSales,
    'base_pay': base.toInt(),
    'commission_pay': commission.toInt(),
    'bonus_pay': bonus,
    'tier_threshold': tierThreshold,
    'total_pay': total.toInt(),
  };
}
