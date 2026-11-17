import type { Actor } from "./auth";
import type { SyncRecord } from "./sync";
import { ApiError, checkPermission, money, text } from "./security";

export async function validateCollections(
  db: D1Database,
  actor: Actor,
  records: SyncRecord[],
): Promise<Set<string>> {
  const documents = new Set(
    records.filter((r) => r.table === "documents").map((r) => r.row.id),
  );
  const payments = records.filter(
    (r) => r.table === "payments" && !documents.has(r.row.document_id),
  );
  const ids = new Set<string>();
  if (!payments.length) return ids;
  checkPermission(actor.role, "collect", actor.issued_role);
  if (documents.size || payments.length !== 1)
    throw new ApiError(400, "Mỗi lần thu nợ cần một giao dịch riêng.");
  for (const { row: pay } of payments) {
    const amount = money(pay.amount);
    if (
      !amount ||
      pay.direction !== "receive" ||
      !["cash", "bank"].includes(String(pay.method))
    )
      throw new ApiError(400, "Thu công nợ không hợp lệ.");
    const doc = await db
      .prepare(
        "SELECT device_id,customer_id FROM documents WHERE store_id=? AND id=? AND ((type='HD' AND kind='sale') OR (type='MR' AND kind='tailoring') OR (type='DT' AND kind IN ('return','exchange')))",
      )
      .bind(actor.store_id, pay.document_id)
      .first<{ device_id: string; customer_id: string }>();
    if (!doc || doc.device_id !== actor.device_id || !doc.customer_id)
      throw new ApiError(
        409,
        "Thu nợ offline cần dùng thiết bị đã lập hóa đơn.",
        "COLLECTION_DEVICE",
      );
    const debts = records.filter((r) => r.table === "receivable_entries");
    if (debts.length !== 1)
      throw new ApiError(400, "Thu nợ cần đúng một bút toán giảm nợ.");
    const debt = debts[0].row;
    if (
      debt.document_id !== pay.document_id ||
      debt.customer_id !== doc.customer_id ||
      debt.payment_id !== pay.id ||
      debt.amount !== -amount ||
      debt.due_date !== ""
    )
      throw new ApiError(400, "Bút toán công nợ không khớp tiền thu.");
    const received = Date.parse(text(pay.created_at, "Ngày thu"));
    if (
      !Number.isFinite(received) ||
      received > Date.now() + 5 * 60000 ||
      debt.created_at !== pay.created_at
    )
      throw new ApiError(400, "Ngày thu không hợp lệ.");
    ids.add(String(pay.id));
  }
  return ids;
}
