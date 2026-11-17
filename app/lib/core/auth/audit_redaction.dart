const auditMask = '[Đã ẩn]';
final _sensitiveAuditKey = RegExp(
  r'password|credential|secret|token|salt|hash|salary|payroll|commission|bonus|compensation|payslip|base_pay|net_pay|gross_pay',
  caseSensitive: false,
);
final _privateAuditAction = RegExp(
  r'^(PAYROLL|SALARY|COMPENSATION|WAGE)_',
  caseSensitive: false,
);
const _payrollAuditIds = {
  'employee_id',
  'user_id',
  'period_id',
  'run_id',
  'slip_id',
  'rule_id',
  'command_id',
  'period_start',
  'period_end',
  'effective_month',
  'status',
  'count',
  'active',
  'role',
  'source_id',
};

Map<String, Object?> redactAuditChanges(
  Map<String, Object?> changes, {
  required String action,
}) {
  Object? redact(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key
              .toString(): _sensitiveAuditKey.hasMatch(entry.key.toString())
              ? auditMask
              : redact(entry.value),
      };
    }
    if (value is List) {
      return value.map(redact).toList();
    }
    return value;
  }

  return {
    for (final entry in changes.entries)
      entry.key:
          _privateAuditAction.hasMatch(action) &&
              !_payrollAuditIds.contains(entry.key)
          ? auditMask
          : _sensitiveAuditKey.hasMatch(entry.key)
          ? auditMask
          : redact(entry.value),
  };
}
