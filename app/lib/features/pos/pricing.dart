import '../../core/money.dart';

/// Giá combo được phân bổ xuống món thành phần bằng số nguyên VND.
/// Mỗi dòng giữ giá áp dụng và phần giảm do làm tròn; không mất một đồng.
class PricedItem {
  const PricedItem({
    required this.id,
    required this.productId,
    required this.price,
    required this.quantity,
  });
  final String id, productId;
  final int price, quantity;
}

class ComboPart {
  const ComboPart(this.productId, this.quantity);
  final String productId;
  final int quantity;
  Map<String, Object?> toJson() => {
    'product_id': productId,
    'quantity': quantity,
  };
  factory ComboPart.fromJson(Map<String, Object?> data) =>
      ComboPart(data['product_id'] as String, data['quantity'] as int);
}

class ComboDefinition {
  const ComboDefinition({
    required this.id,
    required this.version,
    required this.name,
    required this.price,
    required this.parts,
  });
  final String id, version, name;
  final int price;
  final List<ComboPart> parts;
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'name': name,
    'price': price,
    'parts': parts.map((p) => p.toJson()).toList(),
  };
  factory ComboDefinition.fromJson(Map<String, Object?> data) =>
      ComboDefinition(
        id: data['id'] as String,
        version: data['version'] as String,
        name: data['name'] as String,
        price: data['price'] as int,
        parts: (data['parts'] as List)
            .map((v) => ComboPart.fromJson(Map<String, Object?>.from(v as Map)))
            .toList(),
      );
}

class ComboSelection {
  const ComboSelection({
    required this.rule,
    required this.picks,
    this.quantity = 1,
  });
  final ComboDefinition rule;
  final List<String> picks;
  final int quantity;
  Map<String, Object?> toJson() => {
    'rule': rule.toJson(),
    'picks': picks,
    'quantity': quantity,
  };
  Map<String, Object?> toProof() => {
    'rule_id': rule.id,
    'version': rule.version,
    'picks': picks,
    'quantity': quantity,
  };
  factory ComboSelection.fromJson(Map<String, Object?> data) => ComboSelection(
    rule: ComboDefinition.fromJson(
      Map<String, Object?>.from(data['rule'] as Map),
    ),
    picks: List<String>.from(data['picks'] as List),
    quantity: data['quantity'] as int,
  );
}

class ItemPrice {
  const ItemPrice(this.amount, this.unitPrice, this.roundingDiscount);
  final int amount, unitPrice, roundingDiscount;
}

class CartPrice {
  const CartPrice({
    required this.lines,
    required this.regularSubtotal,
    required this.subtotal,
    required this.roundingDiscount,
    required this.amount,
  });
  final Map<String, ItemPrice> lines;
  final int regularSubtotal, subtotal, roundingDiscount, amount;
  int get comboSavings => regularSubtotal - amount;
}

const maximumMoney = 9007199254740991;
int checkedMoney(BigInt value) {
  if (value < BigInt.zero || value > BigInt.from(maximumMoney)) {
    throw StateError('Số tiền vượt giới hạn an toàn.');
  }
  return value.toInt();
}

CartPrice priceCart(List<PricedItem> items, List<ComboSelection> selections) {
  final variants = <String, PricedItem>{},
      remaining = <String, int>{},
      amounts = <String, BigInt>{};
  var regular = BigInt.zero;
  for (final item in items) {
    if (variants.containsKey(item.id) ||
        item.quantity <= 0 ||
        item.price < 0 ||
        item.price > maximumMoney) {
      throw ArgumentError('Dòng tính giá không hợp lệ.');
    }
    variants[item.id] = item;
    remaining[item.id] = item.quantity;
    amounts[item.id] = BigInt.from(item.price) * BigInt.from(item.quantity);
    regular += amounts[item.id]!;
  }
  checkedMoney(regular);
  if (selections.length > 20) {
    throw ArgumentError('Một giỏ có tối đa 20 nhóm combo.');
  }
  for (final selected in selections) {
    final rule = selected.rule;
    if (selected.quantity <= 0 ||
        selected.quantity > 100000 ||
        rule.parts.isEmpty ||
        rule.parts.length > 20 ||
        selected.picks.length != rule.parts.length ||
        rule.price < 0 ||
        rule.price > maximumMoney) {
      throw ArgumentError('Combo hoặc số lượng không hợp lệ.');
    }
    final weights = <int>[];
    for (var index = 0; index < rule.parts.length; index++) {
      final part = rule.parts[index],
          id = selected.picks[index],
          item = variants[id];
      if (part.quantity <= 0 ||
          part.quantity > 100000 ||
          item == null ||
          item.productId != part.productId) {
        throw StateError('Món trong combo không đúng sản phẩm.');
      }
      final required = part.quantity * selected.quantity;
      if ((remaining[id] ?? 0) < required) {
        throw StateError('Giỏ hàng thiếu số lượng của món trong combo.');
      }
      remaining[id] = remaining[id]! - required;
      final baseline = BigInt.from(item.price) * BigInt.from(required);
      weights.add(checkedMoney(baseline));
      amounts[id] = amounts[id]! - baseline;
    }
    final comboAmount = checkedMoney(
      BigInt.from(rule.price) * BigInt.from(selected.quantity),
    );
    final shares = allocateMoney(
      comboAmount,
      weights.every((w) => w == 0) ? List.filled(weights.length, 1) : weights,
    );
    for (var index = 0; index < shares.length; index++) {
      final id = selected.picks[index];
      amounts[id] = amounts[id]! + BigInt.from(shares[index]);
    }
  }
  var net = BigInt.zero, gross = BigInt.zero;
  final lines = <String, ItemPrice>{};
  for (final item in items) {
    final value = amounts[item.id]!, quantity = BigInt.from(item.quantity);
    final unit = (value + quantity - BigInt.one) ~/ quantity,
        rounded = unit * quantity;
    lines[item.id] = ItemPrice(
      checkedMoney(value),
      checkedMoney(unit),
      checkedMoney(rounded - value),
    );
    net += value;
    gross += rounded;
  }
  return CartPrice(
    lines: lines,
    regularSubtotal: checkedMoney(regular),
    subtotal: checkedMoney(gross),
    roundingDiscount: checkedMoney(gross - net),
    amount: checkedMoney(net),
  );
}
