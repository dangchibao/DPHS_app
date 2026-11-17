import 'dart:convert';

import '../pos/pricing.dart';

class CommercialRule {
  CommercialRule({
    required this.id,
    required this.version,
    required this.name,
    required this.kind,
    required this.config,
  }) {
    validate();
  }
  final String id, version, name, kind;
  final Map<String, Object?> config;
  Map<String, Object?> get proof => {'id': id, 'version': version};
  factory CommercialRule.fromRow(Map<String, Object?> row) => CommercialRule(
    id: row['id'] as String,
    version: row['lww_key'] as String,
    name: row['name'] as String,
    kind: row['kind'] as String,
    config: Map<String, Object?>.from(
      jsonDecode(row['config_json'] as String) as Map,
    ),
  );
  Map<String, int> get prices =>
      (config['prices'] as Map).map((k, v) => MapEntry(k as String, v as int));
  static Map<String, Object?> defaults() => {
    'school_id': null,
    'customer_kind': null,
    'starts_at': null,
    'ends_at': null,
    'min_total': 0,
    'min_quantity': 1,
    'allow_combo': false,
    'allow_price_list': false,
    'prices': <String, int>{},
    'discount_type': 'fixed',
    'value': 0,
    'voucher': '',
  };
  void validate() {
    final keys = defaults().keys.toSet();
    Never bad() => throw ArgumentError('Cấu hình giá/khuyến mãi không hợp lệ.');
    if (id.isEmpty ||
        version.isEmpty ||
        name.trim().isEmpty ||
        name.length > 200 ||
        !['price_list', 'promotion'].contains(kind) ||
        config.length != keys.length ||
        config.keys.any((k) => !keys.contains(k))) {
      bad();
    }
    final school = config['school_id'], customer = config['customer_kind'];
    if ((school != null && (school is! String || school.trim().isEmpty)) ||
        (customer != null &&
            !['parent', 'school', 'dealer'].contains(customer))) {
      bad();
    }
    for (final key in ['min_total', 'value']) {
      final n = config[key];
      if (n is! int || n < 0 || n > maximumMoney) {
        bad();
      }
    }
    final count = config['min_quantity'];
    if (count is! int ||
        count < 1 ||
        count > 100000 ||
        config['allow_combo'] is! bool ||
        config['allow_price_list'] is! bool) {
      bad();
    }
    final voucher = config['voucher'];
    if (voucher is! String ||
        !RegExp(r'^[A-Z0-9_-]{0,32}$').hasMatch(voucher)) {
      bad();
    }
    for (final key in ['starts_at', 'ends_at']) {
      final date = config[key];
      if (date != null &&
          (date is! String ||
              DateTime.tryParse(date) == null ||
              DateTime.parse(date).toUtc().toIso8601String() != date)) {
        bad();
      }
    }
    if (config['starts_at'] != null &&
        config['ends_at'] != null &&
        (config['starts_at'] as String).compareTo(
              config['ends_at'] as String,
            ) >=
            0) {
      bad();
    }
    final raw = config['prices'];
    if (raw is! Map || raw.length > 100) {
      bad();
    }
    for (final entry in raw.entries) {
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          entry.value is! int ||
          (entry.value as int) < 0 ||
          (entry.value as int) > maximumMoney) {
        bad();
      }
    }
    final value = config['value'] as int;
    if (kind == 'price_list') {
      if (raw.isEmpty ||
          value != 0 ||
          config['discount_type'] != 'none' ||
          voucher != '' ||
          config['allow_price_list'] != false) {
        bad();
      }
    } else if (raw.isNotEmpty ||
        !['fixed', 'percent'].contains(config['discount_type']) ||
        value < 1 ||
        (config['discount_type'] == 'percent' && value > 10000)) {
      bad();
    }
  }

  void requireEligible({
    String? school,
    String? customerKind,
    required DateTime issuedAt,
    required int quantity,
    required int amount,
    required bool combos,
    String voucher = '',
  }) {
    final c = config;
    if ((c['starts_at'] != null &&
            issuedAt.isBefore(DateTime.parse(c['starts_at'] as String))) ||
        (c['ends_at'] != null &&
            !issuedAt.isBefore(DateTime.parse(c['ends_at'] as String))) ||
        (c['school_id'] != null && c['school_id'] != school) ||
        (c['customer_kind'] != null && c['customer_kind'] != customerKind) ||
        quantity < (c['min_quantity'] as int) ||
        amount < (c['min_total'] as int) ||
        (combos && c['allow_combo'] != true) ||
        c['voucher'] != voucher.trim().toUpperCase()) {
      throw StateError('Đơn chưa đủ điều kiện hoặc ưu đãi không được kết hợp.');
    }
  }

  int discount(int amount, {required int manual, required bool hasPriceList}) {
    if (kind != 'promotion' ||
        manual != 0 ||
        (hasPriceList && config['allow_price_list'] != true)) {
      throw StateError(
        'Khuyến mãi không cộng với giảm thủ công hoặc bảng giá này.',
      );
    }
    final value = config['value'] as int;
    return config['discount_type'] == 'fixed'
        ? (value > amount ? amount : value)
        : checkedMoney(
            BigInt.from(amount) * BigInt.from(value) ~/ BigInt.from(10000),
          );
  }
}

List<PricedItem> applyPriceList(CommercialRule? rule, List<PricedItem> items) =>
    [
      for (final item in items)
        PricedItem(
          id: item.id,
          productId: item.productId,
          price: rule?.prices[item.id] ?? item.price,
          quantity: item.quantity,
        ),
    ];
