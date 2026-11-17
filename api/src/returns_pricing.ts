import { ApiError, money } from "./security";

export type ReplacementGroup = {
  variant_id: string;
  quantity: number;
  source_line_id: string | null;
};
export type ReturnedItem = {
  product_id: string;
  quantity: number;
  credit: number;
};
export type ReplacementVariant = { product_id: string; price: number };
export function priceReplacements(
  groups: ReplacementGroup[],
  returned: Map<string, ReturnedItem>,
  variants: Map<string, ReplacementVariant>,
) {
  if (!Array.isArray(groups) || groups.length > 20)
    throw new ApiError(400, "Tối đa 20 lựa chọn thay thế.");
  const used = new Map<string, number>(),
    counts = new Map<string, number>(),
    amounts = new Map<string, bigint>();
  for (const group of groups) {
    quantity(group.quantity);
    const variant = variants.get(group.variant_id);
    if (!variant) throw new ApiError(400, "Không tìm thấy hàng thay thế.");
    money(variant.price);
    let amount = BigInt(variant.price) * BigInt(group.quantity);
    if (group.source_line_id !== null) {
      const source = returned.get(group.source_line_id),
        before = used.get(group.source_line_id) ?? 0;
      if (
        !source ||
        source.product_id !== variant.product_id ||
        before + group.quantity > source.quantity
      )
        throw new ApiError(
          400,
          "Đổi size cần cùng sản phẩm và không vượt số món nhận lại.",
        );
      amount = BigInt(
        returnCredit(source.credit, source.quantity, before, group.quantity),
      );
      used.set(group.source_line_id, before + group.quantity);
    }
    const count = (counts.get(group.variant_id) ?? 0) + group.quantity;
    quantity(count);
    counts.set(group.variant_id, count);
    amounts.set(
      group.variant_id,
      (amounts.get(group.variant_id) ?? 0n) + amount,
    );
  }
  const total = [...amounts.values()].reduce((a, b) => a + b, 0n);
  if (total > BigInt(Number.MAX_SAFE_INTEGER))
    throw new ApiError(400, "Giá hàng thay thế vượt giới hạn.");
  return new Map(
    [...counts].map(([id, count]) => {
      const amount = amounts.get(id)!,
        unit = (amount + BigInt(count) - 1n) / BigInt(count);
      return [
        id,
        {
          quantity: count,
          amount: Number(amount),
          unit_price: Number(unit),
          discount: Number(unit * BigInt(count) - amount),
        },
      ];
    }),
  );
}

function quantity(n: number, allowZero = false) {
  if (!Number.isSafeInteger(n) || n < (allowZero ? 0 : 1) || n > 100000)
    throw new ApiError(400, "Số lượng đổi/trả không hợp lệ.");
}
export function returnCredit(
  lineNet: number,
  sold: number,
  already: number,
  returned: number,
): number {
  money(lineNet);
  quantity(sold);
  quantity(already, true);
  quantity(returned);
  if (already + returned > sold)
    throw new ApiError(
      409,
      "Số lượng trả vượt số đã mua còn lại.",
      "RETURN_QUANTITY",
    );
  const net = BigInt(lineNet),
    q = BigInt(sold),
    before = BigInt(already),
    delta = BigInt(returned);
  return Number((net * (before + delta)) / q - (net * before) / q);
}
export function exchangeLine(credit: number, count: number) {
  money(credit);
  quantity(count);
  const amount = BigInt(credit),
    n = BigInt(count),
    unit = (amount + n - 1n) / n;
  return { unit_price: Number(unit), discount: Number(unit * n - amount) };
}
export function settleReturn(
  balance: number,
  returnedValue: number,
  replacementValue: number,
  received: number,
) {
  money(balance);
  money(returnedValue);
  money(replacementValue);
  money(received);
  const offset = Math.min(balance, returnedValue),
    due = BigInt(replacementValue) - BigInt(returnedValue) + BigInt(offset);
  if (due < 0n) {
    if (received !== 0)
      throw new ApiError(400, "Phiếu hoàn tiền không thu thêm tiền.");
    return {
      debt_offset: offset,
      cash_due: Number(due),
      refund: Number(-due),
      received: 0,
      new_debt: 0,
      total: Number(-due),
    };
  }
  if (BigInt(received) > due)
    throw new ApiError(400, "Số tiền nhận vượt chênh lệch cần thu.");
  return {
    debt_offset: offset,
    cash_due: Number(due),
    refund: 0,
    received,
    new_debt: Number(due) - received,
    total: Number(due),
  };
}
