import { ApiError, money } from "./security";
export interface PricedItem {
  id: string;
  productId: string;
  price: number;
  quantity: number;
}
export interface ComboPart {
  productId: string;
  quantity: number;
}
export interface ComboDefinition {
  id: string;
  version: string;
  name: string;
  price: number;
  parts: ComboPart[];
}
export interface ComboSelection {
  rule: ComboDefinition;
  picks: string[];
  quantity: number;
}
export interface ItemPrice {
  amount: number;
  unitPrice: number;
  roundingDiscount: number;
}
const maximum = BigInt(Number.MAX_SAFE_INTEGER);
function checked(value: bigint): number {
  if (value < 0n || value > maximum)
    throw new ApiError(400, "Số tiền vượt giới hạn an toàn.");
  return Number(value);
}
export function splitMoney(amount: number, weights: number[]): number[] {
  money(amount);
  if (!weights.length || weights.some((v) => !Number.isSafeInteger(v) || v < 0))
    throw new ApiError(400, "Không thể phân bổ số tiền.");
  const values = weights.every((v) => v === 0) ? weights.map(() => 1) : weights;
  const total = values.reduce((sum, v) => sum + BigInt(v), 0n),
    value = BigInt(amount);
  const result = values.map((v) => Number((value * BigInt(v)) / total));
  const order = values
    .map((_, i) => i)
    .sort((a, b) => {
      const aa = (value * BigInt(values[a])) % total,
        bb = (value * BigInt(values[b])) % total;
      return aa === bb ? a - b : aa > bb ? -1 : 1;
    });
  const left = amount - result.reduce((a, b) => a + b, 0);
  for (let i = 0; i < left; i++) result[order[i]]++;
  return result;
}
export function priceCart(items: PricedItem[], selections: ComboSelection[]) {
  const variants = new Map<string, PricedItem>(),
    remaining = new Map<string, number>(),
    amounts = new Map<string, bigint>();
  let regular = 0n;
  for (const item of items) {
    if (
      variants.has(item.id) ||
      !Number.isSafeInteger(item.quantity) ||
      item.quantity <= 0
    )
      throw new ApiError(400, "Dòng tính giá không hợp lệ.");
    money(item.price);
    variants.set(item.id, item);
    remaining.set(item.id, item.quantity);
    const amount = BigInt(item.price) * BigInt(item.quantity);
    amounts.set(item.id, amount);
    regular += amount;
  }
  checked(regular);
  if (selections.length > 20)
    throw new ApiError(400, "Một giỏ có tối đa 20 nhóm combo.");
  for (const selected of selections) {
    const rule = selected.rule;
    if (
      !Number.isSafeInteger(selected.quantity) ||
      selected.quantity <= 0 ||
      selected.quantity > 100000 ||
      !rule.parts.length ||
      rule.parts.length > 20 ||
      selected.picks.length !== rule.parts.length
    )
      throw new ApiError(400, "Combo hoặc số lượng không hợp lệ.");
    money(rule.price);
    const weights: number[] = [];
    rule.parts.forEach((part, index) => {
      const id = selected.picks[index],
        item = variants.get(id);
      if (
        !Number.isSafeInteger(part.quantity) ||
        part.quantity <= 0 ||
        part.quantity > 100000 ||
        !item ||
        item.productId !== part.productId
      )
        throw new ApiError(400, "Món trong combo không đúng sản phẩm.");
      const required = part.quantity * selected.quantity;
      if ((remaining.get(id) ?? 0) < required)
        throw new ApiError(400, "Giỏ hàng thiếu số lượng của món trong combo.");
      remaining.set(id, remaining.get(id)! - required);
      const baseline = BigInt(item.price) * BigInt(required);
      weights.push(checked(baseline));
      amounts.set(id, amounts.get(id)! - baseline);
    });
    const shares = splitMoney(
      checked(BigInt(rule.price) * BigInt(selected.quantity)),
      weights,
    );
    shares.forEach((amount, index) => {
      const id = selected.picks[index];
      amounts.set(id, amounts.get(id)! + BigInt(amount));
    });
  }
  let net = 0n,
    gross = 0n;
  const lines = new Map<string, ItemPrice>();
  for (const item of items) {
    const value = amounts.get(item.id)!,
      quantity = BigInt(item.quantity);
    const unit = (value + quantity - 1n) / quantity,
      rounded = unit * quantity;
    lines.set(item.id, {
      amount: checked(value),
      unitPrice: checked(unit),
      roundingDiscount: checked(rounded - value),
    });
    net += value;
    gross += rounded;
  }
  return {
    lines,
    regularSubtotal: checked(regular),
    subtotal: checked(gross),
    roundingDiscount: checked(gross - net),
    amount: checked(net),
  };
}
