import { ApiError, checkPermission, money, text } from "./security";
import type { Actor } from "./auth";
import type { SyncRecord } from "./sync";
import {
  returnCredit,
  priceReplacements,
  settleReturn,
  type ReplacementGroup,
  type ReturnedItem,
  type ReplacementVariant,
} from "./returns_pricing";

function object(raw: unknown): Record<string, unknown> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw))
    throw new ApiError(400, "Thông tin đổi/trả không hợp lệ.");
  return raw as Record<string, unknown>;
}
function safe(value: bigint) {
  if (value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER))
    throw new ApiError(400, "Giá trị đổi/trả vượt giới hạn.");
  return Number(value);
}
export async function validateReturns(
  db: D1Database,
  actor: Actor,
  records: SyncRecord[],
): Promise<Set<string>> {
  const docs = records.filter(
    (r) => r.table === "documents" && r.row.type === "DT",
  );
  if (!docs.length) {
    if (
      records.some(
        (r) =>
          ["return_lines", "receivable_adjustments"].includes(r.table) ||
          (r.table === "document_events" && r.row.type === "CANCELLED"),
      )
    )
      throw new ApiError(400, "Thiếu phiếu đổi/trả trong cùng giao dịch.");
    return new Set();
  }
  checkPermission(actor.role, "returns", actor.issued_role);
  if (
    docs.length !== 1 ||
    records.filter((r) => r.table === "documents").length !== 1
  )
    throw new ApiError(400, "Mỗi lần đổi/trả chỉ có một phiếu.");
  const doc = docs[0].row,
    id = text(doc.id, "ID phiếu"),
    originalId = text(doc.original_id, "Hóa đơn gốc");
  let metadata: Record<string, unknown>;
  try {
    metadata = object(JSON.parse(String(doc.metadata_json)));
  } catch {
    throw new ApiError(400, "Snapshot đổi/trả không hợp lệ.");
  }
  const reason = text(metadata.reason, "Lý do đổi/trả"),
    isVoid = metadata.void_original === true;
  if (typeof metadata.void_original !== "boolean")
    throw new ApiError(400, "Thiếu loại thao tác đổi/trả.");
  if (isVoid) checkPermission(actor.role, "voidInvoice", actor.issued_role);
  const allowed = [
    "documents",
    "customers",
    "invoice_lines",
    "return_lines",
    "stock_movements",
    "payments",
    "receivable_entries",
    "receivable_adjustments",
    "document_events",
    "audit_logs",
  ];
  for (const record of records) {
    const r = record.row;
    if (!allowed.includes(record.table))
      throw new ApiError(400, "Loại dữ liệu thừa trong phiếu đổi/trả.");
    if (
      [
        "invoice_lines",
        "return_lines",
        "stock_movements",
        "payments",
        "receivable_entries",
      ].includes(record.table) &&
      r.document_id !== id
    )
      throw new ApiError(400, "Dòng đổi/trả khác phiếu.");
    if (
      record.table === "receivable_adjustments" &&
      (r.credit_document_id !== id || r.document_id !== originalId)
    )
      throw new ApiError(400, "Cấn nợ khác phiếu gốc.");
    if (record.table === "customers" && r.id !== doc.customer_id)
      throw new ApiError(400, "Khách hàng khác phiếu đổi/trả.");
    if (
      record.table === "document_events" &&
      (!isVoid ||
        r.type !== "CANCELLED" ||
        r.document_id !== originalId ||
        r.related_id !== id)
    )
      throw new ApiError(400, "Sự kiện hủy không khớp.");
  }
  const original = await db
    .prepare(
      "SELECT * FROM documents WHERE store_id=? AND id=? AND ((type='HD' AND kind='sale') OR (type='DT' AND kind IN ('return','exchange')))",
    )
    .bind(actor.store_id, originalId)
    .first<Record<string, unknown>>();
  if (
    !original ||
    original.device_id !== actor.device_id ||
    doc.device_id !== actor.device_id ||
    doc.store_id !== actor.store_id
  )
    throw new ApiError(
      409,
      "Đổi/trả offline dùng máy đã lập chứng từ gốc.",
      "RETURN_DEVICE",
    );
  if (original.customer_id !== null && doc.customer_id !== original.customer_id)
    throw new ApiError(400, "Khách đổi/trả không khớp hóa đơn gốc.");
  if (metadata.original_code !== original.code)
    throw new ApiError(400, "Mã chứng từ gốc trong snapshot không khớp.");
  if (isVoid && original.type !== "HD")
    throw new ApiError(400, "Chỉ hủy hóa đơn HD theo luồng này.");
  // Retry document bất biến vẫn qua kiểm tra toàn bộ nội dung/đủ dòng ở sync.ts.
  if (
    await db
      .prepare("SELECT id FROM documents WHERE store_id=? AND id=?")
      .bind(actor.store_id, id)
      .first()
  )
    return new Set([id]);
  if (
    await db
      .prepare(
        "SELECT id FROM document_events WHERE store_id=? AND document_id=? AND type='CANCELLED'",
      )
      .bind(actor.store_id, originalId)
      .first()
  )
    throw new ApiError(409, "Chứng từ đã hủy.");
  const issued = Date.parse(text(doc.issued_at, "Ngày phiếu"));
  if (
    !Number.isFinite(issued) ||
    issued > Date.now() + 300000 ||
    issued < Date.parse(String(original.issued_at))
  )
    throw new ApiError(
      409,
      "Đồng hồ phiếu đổi/trả không hợp lệ.",
      "CLOCK_SKEW",
    );
  const day = new Date(issued + 7 * 3600000)
    .toISOString()
    .slice(0, 10)
    .replaceAll("-", "");
  const store = await db
      .prepare("SELECT code FROM stores WHERE id=?")
      .bind(actor.store_id)
      .first<{ code: string }>(),
    device = await db
      .prepare("SELECT code FROM devices WHERE store_id=? AND id=?")
      .bind(actor.store_id, actor.device_id)
      .first<{ code: string }>();
  const prefix = `DT-${store?.code.replace(/^NT-/, "")}-${device?.code}-${day}-`;
  if (
    typeof doc.code !== "string" ||
    !doc.code.startsWith(prefix) ||
    !/^\d{3,}$/.test(doc.code.slice(prefix.length)) ||
    Number(doc.code.slice(prefix.length)) < 1
  )
    throw new ApiError(400, "Mã phiếu đổi/trả không khớp.");
  const returnRows = records
    .filter((r) => r.table === "return_lines")
    .map((r) => r.row);
  if (!returnRows.length || returnRows.length > 48)
    throw new ApiError(400, "Chọn từ 1 đến 48 dòng nhận lại.");
  const sources = new Map<string, ReturnedItem>(),
    inStock = new Map<string, number>();
  let returnedTotal = 0n;
  const sourceRows = await db.batch(
    returnRows.map((r) =>
      db
        .prepare(
          "SELECT l.*,v.product_id,COALESCE((SELECT SUM(quantity) FROM return_lines WHERE store_id=l.store_id AND original_line_id=l.id),0) AS returned FROM invoice_lines l JOIN product_variants v ON v.id=l.variant_id WHERE l.store_id=? AND l.id=? AND l.document_id=?",
        )
        .bind(
          actor.store_id,
          text(r.original_line_id, "Dòng hàng gốc"),
          originalId,
        ),
    ),
  );
  let sourceIndex = 0;
  for (const r of returnRows) {
    if (!Number.isSafeInteger(r.quantity))
      throw new ApiError(400, "Số lượng nhận lại phải là số nguyên.");
    const lineId = text(r.original_line_id, "Dòng hàng gốc");
    if (sources.has(lineId))
      throw new ApiError(400, "Mỗi dòng gốc chỉ nhận một lần trong phiếu.");
    const source = sourceRows[sourceIndex++]?.results?.[0] as
      Record<string, unknown> | undefined;
    if (!source) throw new ApiError(400, "Dòng hàng không thuộc chứng từ gốc.");
    const lineNet = safe(
      BigInt(Number(source.unit_price)) * BigInt(Number(source.quantity)) -
        BigInt(Number(source.discount)),
    );
    const credit = returnCredit(
      lineNet,
      Number(source.quantity),
      Number(source.returned),
      Number(r.quantity),
    );
    if (r.base_returned !== source.returned || r.credit !== credit)
      throw new ApiError(
        409,
        "Số món/giá trị trả đã thay đổi.",
        "RETURN_QUANTITY",
      );
    sources.set(lineId, {
      product_id: String(source.product_id),
      quantity: Number(r.quantity),
      credit,
    });
    returnedTotal += BigInt(credit);
    inStock.set(
      String(source.variant_id),
      (inStock.get(String(source.variant_id)) ?? 0) + Number(r.quantity),
    );
  }
  const returnedValue = safe(returnedTotal);
  const rawGroups = metadata.replacements;
  if (!Array.isArray(rawGroups) || rawGroups.length > 20)
    throw new ApiError(400, "Lựa chọn hàng thay thế không hợp lệ.");
  const groups: ReplacementGroup[] = rawGroups.map((raw) => {
    const g = object(raw);
    if (!Number.isSafeInteger(g.quantity))
      throw new ApiError(400, "Số lượng thay thế phải là số nguyên.");
    if (
      Object.keys(g).length !== 3 ||
      Object.keys(g).some(
        (k) => !["variant_id", "quantity", "source_line_id"].includes(k),
      )
    )
      throw new ApiError(400, "Thông tin hàng thay thế thừa trường.");
    return {
      variant_id: text(g.variant_id, "Hàng thay thế"),
      quantity: Number(g.quantity),
      source_line_id:
        g.source_line_id === null
          ? null
          : text(g.source_line_id, "Dòng đổi size"),
    };
  });
  if (
    doc.kind !== (groups.length ? "exchange" : "return") ||
    (isVoid && groups.length)
  )
    throw new ApiError(400, "Loại phiếu đổi/trả không khớp hàng thay thế.");
  const newLines = records
      .filter((r) => r.table === "invoice_lines")
      .map((r) => r.row),
    variants = new Map<string, ReplacementVariant>();
  const histories = newLines.length
    ? await db.batch(
        newLines.map((line) =>
          db
            .prepare(
              "SELECT h.price,h.cost,v.product_id FROM variant_price_history h JOIN product_variants v ON v.id=h.variant_id WHERE h.variant_id=? AND h.version=?",
            )
            .bind(
              text(line.variant_id, "Biến thể thay thế"),
              text(line.price_version, "Phiên bản giá"),
            ),
        ),
      )
    : [];
  let historyIndex = 0;
  for (const line of newLines) {
    const variant = text(line.variant_id, "Biến thể thay thế");
    if (variants.has(variant))
      throw new ApiError(400, "Gộp dòng cùng biến thể thay thế.");
    const history = histories[historyIndex++]?.results?.[0] as
      { price: number; cost: number; product_id: string } | undefined;
    if (!history || line.unit_cost !== history.cost)
      throw new ApiError(
        409,
        "Không xác minh được giá/cost hàng thay thế.",
        "PRICE_VERSION",
      );
    variants.set(variant, {
      product_id: history.product_id,
      price: history.price,
    });
  }
  const plan = priceReplacements(groups, sources, variants);
  if (plan.size !== newLines.length)
    throw new ApiError(400, "Dòng hàng thay thế không khớp lựa chọn.");
  let replacementTotal = 0n;
  for (const line of newLines) {
    const p = plan.get(String(line.variant_id));
    if (
      !p ||
      line.quantity !== p.quantity ||
      line.unit_price !== p.unit_price ||
      line.discount !== p.discount
    )
      throw new ApiError(400, "Giá trị hàng thay thế không khớp.");
    replacementTotal += BigInt(p.amount);
  }
  const replacementValue = safe(replacementTotal),
    balanceRow = await db
      .prepare(
        "SELECT COALESCE(SUM(amount),0) AS balance FROM receivable_ledger WHERE store_id=? AND document_id=?",
      )
      .bind(actor.store_id, originalId)
      .first<{ balance: number }>();
  const settlement = settleReturn(
    balanceRow?.balance ?? 0,
    returnedValue,
    replacementValue,
    money(metadata.received),
  );
  for (const [key, value] of Object.entries({
    ...settlement,
    returned_value: returnedValue,
    replacement_value: replacementValue,
  }))
    if (metadata[key] !== value)
      throw new ApiError(400, `Cân bằng phiếu đổi/trả không khớp: ${key}`);
  if (
    doc.subtotal !== settlement.total ||
    doc.discount !== 0 ||
    doc.total !== settlement.total
  )
    throw new ApiError(400, "Tổng phiếu đổi/trả không khớp.");
  const payments = records
      .filter((r) => r.table === "payments")
      .map((r) => r.row),
    cash = settlement.refund || settlement.received;
  if (payments.length !== (cash ? 1 : 0))
    throw new ApiError(400, "Số giao dịch thu/hoàn không khớp.");
  if (cash) {
    const p = payments[0];
    if (
      p.amount !== cash ||
      p.direction !== (settlement.refund ? "refund" : "receive") ||
      !["cash", "bank"].includes(String(p.method)) ||
      p.created_at !== doc.issued_at
    )
      throw new ApiError(400, "Tiền thu/hoàn không khớp.");
  }
  const debts = records
    .filter((r) => r.table === "receivable_entries")
    .map((r) => r.row);
  if (debts.length !== (settlement.new_debt ? 1 : 0))
    throw new ApiError(400, "Công nợ mới không khớp.");
  if (settlement.new_debt) {
    const d = debts[0];
    if (
      !doc.customer_id ||
      d.customer_id !== doc.customer_id ||
      d.payment_id !== null ||
      d.amount !== settlement.new_debt ||
      d.created_at !== doc.issued_at ||
      typeof d.due_date !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(d.due_date) ||
      !Number.isFinite(Date.parse(`${d.due_date}T00:00:00.000Z`)) ||
      new Date(`${d.due_date}T00:00:00.000Z`).toISOString().slice(0, 10) !==
        d.due_date ||
      d.due_date < new Date(issued + 7 * 3600000).toISOString().slice(0, 10)
    )
      throw new ApiError(400, "Chi tiết nợ mới không khớp.");
  }
  const credits = records
    .filter((r) => r.table === "receivable_adjustments")
    .map((r) => r.row);
  if (credits.length !== (settlement.debt_offset ? 1 : 0))
    throw new ApiError(400, "Cấn công nợ không khớp.");
  if (settlement.debt_offset) {
    const c = credits[0];
    if (
      c.amount !== -settlement.debt_offset ||
      c.customer_id !== original.customer_id ||
      c.created_at !== doc.issued_at
    )
      throw new ApiError(400, "Bút toán cấn nợ không khớp.");
  }
  const actualIn = new Map<string, number>(),
    actualOut = new Map<string, number>();
  for (const r of records
    .filter((r) => r.table === "stock_movements")
    .map((r) => r.row)) {
    if (r.created_at !== doc.issued_at)
      throw new ApiError(400, "Ngày kho đổi/trả không khớp phiếu.");
    if (!Number.isSafeInteger(r.quantity) || Number(r.quantity) === 0)
      throw new ApiError(400, "Kho đổi/trả không hợp lệ.");
    const target =
      r.kind === "return" && Number(r.quantity) > 0
        ? actualIn
        : r.kind === "sale" && Number(r.quantity) < 0
          ? actualOut
          : null;
    if (!target) throw new ApiError(400, "Loại kho đổi/trả không hợp lệ.");
    const variant = String(r.variant_id);
    target.set(
      variant,
      (target.get(variant) ?? 0) + Math.abs(Number(r.quantity)),
    );
  }
  if (
    actualIn.size !== inStock.size ||
    [...inStock].some(([id, q]) => actualIn.get(id) !== q) ||
    actualOut.size !== plan.size ||
    [...plan].some(([id, p]) => actualOut.get(id) !== p.quantity)
  )
    throw new ApiError(400, "Kho không khớp hàng nhận lại/thay thế.");
  const events = records.filter((r) => r.table === "document_events");
  if (events.length !== (isVoid ? 1 : 0))
    throw new ApiError(400, "Sự kiện hủy không khớp.");
  if (isVoid) {
    const remaining = await db
      .prepare(
        "SELECT l.id,l.quantity-COALESCE((SELECT SUM(quantity) FROM return_lines WHERE store_id=l.store_id AND original_line_id=l.id),0) AS remaining FROM invoice_lines l WHERE l.store_id=? AND l.document_id=?",
      )
      .bind(actor.store_id, originalId)
      .all<{ id: string; remaining: number }>();
    const nonzero = remaining.results.filter((l) => l.remaining > 0);
    if (
      nonzero.length !== sources.size ||
      nonzero.some((l) => sources.get(l.id)?.quantity !== l.remaining)
    )
      throw new ApiError(400, "Hủy cần nhận lại toàn bộ số món còn lại.");
    const e = events[0].row;
    if (
      e.reason !== reason ||
      e.created_at !== doc.issued_at ||
      e.user_id !== actor.user_id
    )
      throw new ApiError(400, "Chi tiết hủy không khớp.");
  }
  return new Set([id]);
}
