import '../pos/pricing.dart';

void _quantity(int n, {bool zero = false}) {
  if (n < (zero ? 0 : 1) || n > 100000) {
    throw ArgumentError('Số lượng đổi/trả không hợp lệ.');
  }
}

int returnCredit(int net, int sold, int already, int returned) {
  checkedMoney(BigInt.from(net));
  _quantity(sold);
  _quantity(already, zero: true);
  _quantity(returned);
  if (already + returned > sold) {
    throw StateError('Số lượng trả vượt số đã mua còn lại.');
  }
  final value = BigInt.from(net), count = BigInt.from(sold);
  return (value * BigInt.from(already + returned) ~/ count -
          value * BigInt.from(already) ~/ count)
      .toInt();
}

class ReturnSettlement {
  ReturnSettlement(
    this.offset,
    this.cashDue,
    this.refund,
    this.received,
    this.newDebt,
    this.total,
  );
  final int offset, cashDue, refund, received, newDebt, total;
}

ReturnSettlement settleReturn(
  int balance,
  int returned,
  int replacement,
  int received,
) {
  for (final n in [balance, returned, replacement, received]) {
    checkedMoney(BigInt.from(n));
  }
  final offset = balance < returned ? balance : returned,
      due =
          BigInt.from(replacement) -
          BigInt.from(returned) +
          BigInt.from(offset);
  if (due < BigInt.zero) {
    if (received != 0) {
      throw ArgumentError('Phiếu hoàn tiền không thu thêm tiền.');
    }
    return ReturnSettlement(
      offset,
      due.toInt(),
      (-due).toInt(),
      0,
      0,
      (-due).toInt(),
    );
  }
  if (BigInt.from(received) > due) {
    throw ArgumentError('Số tiền nhận vượt chênh lệch cần thu.');
  }
  return ReturnSettlement(
    offset,
    due.toInt(),
    0,
    received,
    due.toInt() - received,
    due.toInt(),
  );
}

class ReturnSelection {
  const ReturnSelection(this.lineId, this.quantity);
  final String lineId;
  final int quantity;
  Map<String, Object?> toJson() => {'line_id': lineId, 'quantity': quantity};
}

class ReplacementSelection {
  const ReplacementSelection(
    this.variantId,
    this.quantity, {
    this.sourceLineId,
  });
  final String variantId;
  final int quantity;
  final String? sourceLineId;
  Map<String, Object?> toJson() => {
    'variant_id': variantId,
    'quantity': quantity,
    'source_line_id': sourceLineId,
  };
}

class ReturnedItem {
  ReturnedItem({
    required this.productId,
    required this.quantity,
    required this.credit,
  });
  final String productId;
  final int quantity, credit;
}

class ReplacementVariant {
  ReplacementVariant(this.productId, this.price);
  final String productId;
  final int price;
}

class ReplacementPrice {
  ReplacementPrice(this.quantity, this.amount, this.unitPrice, this.discount);
  final int quantity, amount, unitPrice, discount;
}

Map<String, ReplacementPrice> priceReplacements(
  List<ReplacementSelection> groups,
  Map<String, ReturnedItem> returned,
  Map<String, ReplacementVariant> variants,
) {
  if (groups.length > 20) {
    throw ArgumentError('Tối đa 20 lựa chọn thay thế.');
  }
  final used = <String, int>{},
      counts = <String, int>{},
      amounts = <String, BigInt>{};
  for (final group in groups) {
    _quantity(group.quantity);
    final variant = variants[group.variantId];
    if (variant == null) {
      throw StateError('Không tìm thấy hàng thay thế.');
    }
    checkedMoney(BigInt.from(variant.price));
    var amount = BigInt.from(variant.price) * BigInt.from(group.quantity);
    if (group.sourceLineId != null) {
      final source = returned[group.sourceLineId],
          before = used[group.sourceLineId] ?? 0;
      if (source == null ||
          source.productId != variant.productId ||
          before + group.quantity > source.quantity) {
        throw StateError(
          'Đổi size cần cùng sản phẩm và không vượt số món nhận lại.',
        );
      }
      amount = BigInt.from(
        returnCredit(source.credit, source.quantity, before, group.quantity),
      );
      used[group.sourceLineId!] = before + group.quantity;
    }
    counts.update(
      group.variantId,
      (n) => n + group.quantity,
      ifAbsent: () => group.quantity,
    );
    _quantity(counts[group.variantId]!);
    amounts.update(group.variantId, (n) => n + amount, ifAbsent: () => amount);
  }
  checkedMoney(amounts.values.fold(BigInt.zero, (a, b) => a + b));
  return {
    for (final id in counts.keys)
      id: (() {
        final count = counts[id]!,
            amount = amounts[id]!,
            unit =
                (amount + BigInt.from(count) - BigInt.one) ~/
                BigInt.from(count);
        return ReplacementPrice(
          count,
          checkedMoney(amount),
          checkedMoney(unit),
          (unit * BigInt.from(count) - amount).toInt(),
        );
      })(),
  };
}
