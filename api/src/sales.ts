import { ApiError, money, text } from "./security";
import type { Actor } from "./auth";
import type { SyncRecord } from "./sync";
import { priceCart, type PricedItem } from "./pricing";
import { loadComboSelections } from "./combos";
import { tailorPricing } from "./tailoring";
import {
  loadCommercialRule,
  eligible,
  priceListItems,
  promotionDiscount,
} from "./commercial";

export async function validateSales(
  db: D1Database,
  actor: Actor,
  records: SyncRecord[],
  collectionPayments: Set<string> = new Set(),
  returnDocuments: Set<string> = new Set(),
): Promise<Set<string>> {
  const documents = records
      .filter(
        (r) =>
          r.table === "documents" && !returnDocuments.has(String(r.row.id)),
      )
      .map((r) => r.row),
    ids = new Set<string>();
  if (documents.length > 1)
    throw new ApiError(400, "Mỗi mutation chỉ có một chứng từ.");
  for (const doc of documents) {
    const isTailoring = doc.type === "MR" && doc.kind === "tailoring";
    if (
      (!isTailoring && (doc.type !== "HD" || doc.kind !== "sale")) ||
      doc.original_id !== null
    )
      throw new ApiError(
        400,
        "Loại chứng từ chưa được phép qua luồng bán hàng.",
      );
    const id = text(doc.id, "ID hóa đơn");
    ids.add(id);
    if (isTailoring && !doc.customer_id)
      throw new ApiError(400, "Đơn may cần khách hàng.");
    let context: Record<string, unknown>;
    try {
      const value: unknown = JSON.parse(String(doc.metadata_json));
      if (!value || typeof value !== "object" || Array.isArray(value))
        throw new Error();
      context = value as Record<string, unknown>;
    } catch {
      throw new ApiError(400, "Thông tin snapshot hóa đơn không hợp lệ.");
    }
    if (context.held_cart_id != null) text(context.held_cart_id, "Mã đơn tạm");
    if (context.school_id != null) {
      const school = await db
        .prepare("SELECT customer_id FROM schools WHERE store_id=? AND id=?")
        .bind(actor.store_id, text(context.school_id, "Trường"))
        .first<{ customer_id: string }>();
      if (!school) throw new ApiError(403, "Trường không thuộc cửa hàng.");
      if (context.student_id == null && school.customer_id !== doc.customer_id)
        throw new ApiError(400, "Đơn tập thể không khớp công nợ của trường.");
    }
    if (context.student_id != null) {
      const student = await db
        .prepare(
          "SELECT st.customer_id,cl.school_id FROM students st JOIN school_classes cl ON cl.store_id=st.store_id AND cl.id=st.class_id WHERE st.store_id=? AND st.id=?",
        )
        .bind(actor.store_id, text(context.student_id, "Học sinh"))
        .first<{ customer_id: string; school_id: string }>();
      if (
        !student ||
        student.customer_id !== doc.customer_id ||
        !context.school_id ||
        student.school_id !== context.school_id
      )
        throw new ApiError(403, "Học sinh hoặc phụ huynh không khớp cửa hàng.");
    }
    const subtotal = money(doc.subtotal),
      discount = money(doc.discount),
      total = money(doc.total);
    if (total !== subtotal - discount)
      throw new ApiError(400, "Tổng hóa đơn không khớp.");
    const lines = records
      .filter((r) => r.table === "invoice_lines" && r.row.document_id === id)
      .map((r) => r.row);
    if (lines.length === 0)
      throw new ApiError(400, "Hóa đơn không có dòng hàng.");
    if (isTailoring && lines.length > 20)
      throw new ApiError(400, "Đơn may tối đa 20 dòng.");
    let gross = 0n,
      lineDiscount = 0n;
    const quantities = new Map<string, number>();
    const pricingItems: PricedItem[] = [];
    const histories = await db.batch(
      lines.map((line) =>
        db
          .prepare(
            "SELECT h.price,h.cost,v.product_id FROM variant_price_history h JOIN product_variants v ON v.id=h.variant_id WHERE h.variant_id=? AND h.version=?",
          )
          .bind(line.variant_id, line.price_version),
      ),
    );
    let lineIndex = 0;
    for (const line of lines) {
      if (
        !Number.isSafeInteger(line.quantity) ||
        (line.quantity as number) <= 0
      )
        throw new ApiError(400, "Số lượng dòng hàng không hợp lệ.");
      money(line.unit_price);
      money(line.unit_cost);
      money(line.discount);
      const value =
        BigInt(line.unit_price as number) * BigInt(line.quantity as number);
      if (BigInt(line.discount as number) > value)
        throw new ApiError(400, "Giảm giá dòng hàng không hợp lệ.");
      gross += value;
      lineDiscount += BigInt(line.discount as number);
      const history = histories[lineIndex++]?.results?.[0] as
        { price: number; cost: number; product_id: string } | undefined;
      if (!history || history.cost !== line.unit_cost)
        throw new ApiError(
          409,
          "Không xác minh được phiên bản giá bán offline.",
          "PRICE_VERSION",
        );
      const variant = String(line.variant_id);
      if (quantities.has(variant))
        throw new ApiError(
          400,
          "Gộp các dòng cùng biến thể trước khi thanh toán.",
        );
      pricingItems.push({
        id: variant,
        productId: history.product_id,
        price: history.price,
        quantity: line.quantity as number,
      });
      quantities.set(
        variant,
        (quantities.get(variant) ?? 0) + (line.quantity as number),
      );
    }
    if (gross !== BigInt(subtotal) || lineDiscount !== BigInt(discount))
      throw new ApiError(400, "Tổng dòng hàng không khớp hóa đơn.");
    const comboSelections = await loadComboSelections(
      db,
      actor,
      context.combo_groups,
      String(doc.issued_at),
    );
    if (
      isTailoring &&
      (comboSelections.length ||
        context.price_list != null ||
        context.promotion != null ||
        discount !== 0)
    )
      throw new ApiError(
        400,
        "Đơn may dùng bảng phụ thu riêng, không gộp combo/khuyến mãi/giảm thủ công.",
      );
    const adjustedItems = isTailoring
      ? await tailorPricing(
          db,
          actor,
          context.tailoring,
          String(doc.issued_at),
          pricingItems,
        )
      : pricingItems;
    const priceList = await loadCommercialRule(
      db,
      actor,
      context.price_list,
      "price_list",
      String(doc.issued_at),
    );
    const promotion = await loadCommercialRule(
      db,
      actor,
      context.promotion,
      "promotion",
      String(doc.issued_at),
    );
    const customer =
      doc.customer_id == null
        ? null
        : await db
            .prepare("SELECT kind FROM customers WHERE store_id=? AND id=?")
            .bind(actor.store_id, doc.customer_id)
            .first<{ kind: string }>();
    const pendingCustomer = records.find(
      (r) => r.table === "customers" && r.row.id === doc.customer_id,
    )?.row;
    const conditions = {
      school: context.school_id,
      customerKind: customer?.kind ?? pendingCustomer?.kind ?? "parent",
      issuedAt: String(doc.issued_at),
      quantity: pricingItems.reduce((n, i) => n + i.quantity, 0),
      amount: priceCart(pricingItems, []).amount,
      combos: comboSelections.length > 0,
    };
    if (priceList) eligible(priceList, conditions);
    const pricing = priceCart(
      priceListItems(priceList, adjustedItems),
      comboSelections,
    );
    if (promotion)
      eligible(
        promotion,
        { ...conditions, amount: pricing.amount },
        typeof context.voucher === "string" ? context.voucher : "",
      );
    const promoDiscount = promotionDiscount(
      promotion,
      pricing.amount,
      Number(context.manual_discount ?? 0),
      priceList !== null,
    );
    if (
      (promotion && context.promotion_discount !== promoDiscount) ||
      (!promotion &&
        context.promotion_discount != null &&
        context.promotion_discount !== 0)
    )
      throw new ApiError(400, "Giảm khuyến mãi không khớp.");
    for (const line of lines) {
      const expected = pricing.lines.get(String(line.variant_id))!;
      if (
        line.unit_price !== expected.unitPrice ||
        (line.discount as number) < expected.roundingDiscount
      )
        throw new ApiError(
          409,
          "Không xác minh được phiên bản giá bán offline.",
          "PRICE_VERSION",
        );
    }
    const manualDiscount =
      BigInt(discount) -
      BigInt(pricing.roundingDiscount) -
      BigInt(promoDiscount);
    if (promotion && manualDiscount !== 0n)
      throw new ApiError(400, "Khuyến mãi không cộng thêm giảm thủ công.");
    if (
      manualDiscount < 0n ||
      (context.manual_discount !== undefined &&
        BigInt(money(context.manual_discount)) !== manualDiscount)
    )
      throw new ApiError(400, "Giảm giá thủ công không khớp.");
    if (
      context.regular_subtotal !== undefined &&
      money(context.regular_subtotal) !== pricing.regularSubtotal
    )
      throw new ApiError(400, "Giá lẻ snapshot không khớp.");
    if (actor.role === "cashier" || actor.issued_role === "cashier") {
      const setting = await db
        .prepare(
          "SELECT value FROM store_settings WHERE store_id=? AND key='cashier_discount_percent'",
        )
        .bind(actor.store_id)
        .first<{ value: string }>();
      const percent = Number(setting?.value ?? 10);
      if (manualDiscount * 100n > BigInt(pricing.amount) * BigInt(percent))
        throw new ApiError(403, "Giảm giá vượt quyền thu ngân.");
    }
    const movements = records
      .filter((r) => r.table === "stock_movements" && r.row.document_id === id)
      .map((r) => r.row);
    const moved = new Map<string, number>();
    for (const movement of movements) {
      if (
        movement.kind !== "sale" ||
        !Number.isSafeInteger(movement.quantity) ||
        (movement.quantity as number) >= 0
      )
        throw new ApiError(400, "Xuất kho bán hàng không hợp lệ.");
      const variant = String(movement.variant_id);
      moved.set(
        variant,
        (moved.get(variant) ?? 0) - (movement.quantity as number),
      );
    }
    if (
      isTailoring
        ? movements.length !== 0
        : moved.size !== quantities.size ||
          [...quantities].some(
            ([variant, quantity]) => moved.get(variant) !== quantity,
          )
    )
      throw new ApiError(400, "Xuất kho không khớp dòng hàng.");
    const payments = records
      .filter((r) => r.table === "payments" && r.row.document_id === id)
      .map((r) => r.row);
    let paid = 0n;
    for (const payment of payments) {
      if (
        payment.direction !== "receive" ||
        !["cash", "bank"].includes(String(payment.method)) ||
        money(payment.amount) === 0
      )
        throw new ApiError(400, "Thanh toán không hợp lệ.");
      paid += BigInt(payment.amount as number);
    }
    if (paid > BigInt(total))
      throw new ApiError(400, "Số tiền thu lớn hơn giá trị hóa đơn.");
    const debts = records
      .filter(
        (r) => r.table === "receivable_entries" && r.row.document_id === id,
      )
      .map((r) => r.row);
    let outstanding = 0n;
    for (const debt of debts) {
      if (debt.customer_id !== doc.customer_id || debt.payment_id !== null)
        throw new ApiError(400, "Công nợ không khớp khách hàng.");
      outstanding += BigInt(money(debt.amount));
    }
    if (
      outstanding !== BigInt(total) - paid ||
      (outstanding > 0n && !doc.customer_id)
    )
      throw new ApiError(400, "Công nợ không khớp thanh toán.");
    const store = await db
      .prepare("SELECT code FROM stores WHERE id=?")
      .bind(actor.store_id)
      .first<{ code: string }>();
    const device = await db
      .prepare("SELECT code FROM devices WHERE store_id=? AND id=?")
      .bind(actor.store_id, actor.device_id)
      .first<{ code: string }>();
    const issued = Date.parse(text(doc.issued_at, "Ngày hóa đơn"));
    if (!Number.isFinite(issued) || issued > Date.now() + 5 * 60000)
      throw new ApiError(409, "Đồng hồ thiết bị sai.", "CLOCK_SKEW");
    const day = new Date(issued + 7 * 3600000)
      .toISOString()
      .slice(0, 10)
      .replaceAll("-", "");
    const prefix = `${doc.type}-${store?.code.replace(/^NT-/, "")}-${device?.code}-${day}-`;
    if (
      typeof doc.code !== "string" ||
      !doc.code.startsWith(prefix) ||
      !/^\d{3,}$/.test(doc.code.slice(prefix.length)) ||
      Number(doc.code.slice(prefix.length)) < 1
    )
      throw new ApiError(400, "Mã hóa đơn không khớp cửa hàng/thiết bị/ngày.");
  }
  for (const record of records) {
    if (
      ["invoice_lines", "payments", "receivable_entries"].includes(
        record.table,
      ) &&
      !ids.has(String(record.row.document_id)) &&
      !returnDocuments.has(String(record.row.document_id)) &&
      !(
        record.table === "payments" &&
        collectionPayments.has(String(record.row.id))
      ) &&
      !(
        record.table === "receivable_entries" &&
        collectionPayments.has(String(record.row.payment_id))
      )
    )
      throw new ApiError(
        400,
        "Dòng nghiệp vụ thiếu chứng từ trong cùng bundle.",
      );
  }
  return ids;
}
