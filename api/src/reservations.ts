import type { Actor } from "./auth";
import type { SyncRecord } from "./sync";
import { ApiError, checkPermission, money, text } from "./security";
import { utcInstant, reservationState } from "./reservation_time";

function metadata(row: Record<string, unknown>): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(String(row.metadata_json));
    if (!value || typeof value !== "object" || Array.isArray(value))
      throw new Error();
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "Thông tin giữ hàng không hợp lệ.");
  }
}

export async function validateReservations(
  db: D1Database,
  actor: Actor,
  records: SyncRecord[],
): Promise<Set<string>> {
  const documents = records
    .filter((r) => r.table === "documents" && r.row.type === "DH")
    .map((r) => r.row);
  const ids = new Set<string>();
  if (documents.length > 1)
    throw new ApiError(400, "Mỗi lần chỉ lập một phiếu giữ hàng.");
  for (const doc of documents) {
    checkPermission(actor.role, "sell", actor.issued_role);
    const id = text(doc.id, "Phiếu giữ"),
      m = metadata(doc),
      issued = utcInstant(doc.issued_at, "Ngày giữ"),
      expiry = utcInstant(m.expires_at, "Hạn giữ");
    ids.add(id);
    if (
      doc.kind !== "reservation" ||
      doc.original_id !== null ||
      !doc.customer_id ||
      doc.store_id !== actor.store_id ||
      doc.device_id !== actor.device_id ||
      doc.user_id !== actor.user_id ||
      issued > Date.now() + 300000 ||
      expiry - issued < 60000 ||
      expiry - issued > 30 * 86400000
    )
      throw new ApiError(400, "Phiếu giữ hàng không hợp lệ.");
    const lines = records
        .filter((r) => r.table === "invoice_lines" && r.row.document_id === id)
        .map((r) => r.row),
      holds = records
        .filter(
          (r) => r.table === "reservation_lines" && r.row.document_id === id,
        )
        .map((r) => r.row);
    if (
      !lines.length ||
      lines.length > 20 ||
      holds.length !== lines.length ||
      records.some(
        (r) =>
          ![
            "customers",
            "documents",
            "invoice_lines",
            "reservation_lines",
            "audit_logs",
          ].includes(r.table),
      )
    )
      throw new ApiError(
        400,
        "Phiếu giữ không được ghi thanh toán, công nợ hoặc kho.",
      );
    const versions = await db.batch<Record<string, unknown>>(
      lines.map((l) =>
        db
          .prepare(
            "SELECT price,cost FROM variant_price_history WHERE variant_id=? AND version=?",
          )
          .bind(l.variant_id, l.price_version),
      ),
    );
    let total = 0n;
    const seen = new Set<unknown>();
    for (let i = 0; i < lines.length; i++) {
      const l = lines[i],
        h = holds.find((h) => h.variant_id === l.variant_id),
        version = versions[i]?.results?.[0];
      if (
        !Number.isSafeInteger(l.quantity) ||
        Number(l.quantity) < 1 ||
        Number(l.quantity) > 100000 ||
        seen.has(l.variant_id) ||
        !h ||
        h.quantity !== l.quantity ||
        h.created_at !== doc.issued_at ||
        h.expires_at !== m.expires_at ||
        !version ||
        version.price !== l.unit_price ||
        version.cost !== l.unit_cost ||
        l.discount !== 0
      )
        throw new ApiError(400, "Dòng giữ hàng không khớp số lượng/giá.");
      seen.add(l.variant_id);
      total += BigInt(money(l.unit_price)) * BigInt(Number(l.quantity));
    }
    if (
      BigInt(money(doc.total)) !== total ||
      doc.subtotal !== doc.total ||
      doc.discount !== 0
    )
      throw new ApiError(400, "Tổng báo giá không khớp.");
    const identities = await db.batch<Record<string, unknown>>([
      db.prepare("SELECT code FROM stores WHERE id=?").bind(actor.store_id),
      db
        .prepare("SELECT code FROM devices WHERE store_id=? AND id=?")
        .bind(actor.store_id, actor.device_id),
      db
        .prepare("SELECT id FROM customers WHERE store_id=? AND id=?")
        .bind(actor.store_id, doc.customer_id),
    ]);
    if (
      !identities[2].results?.length &&
      !records.some(
        (r) =>
          r.table === "customers" &&
          r.row.id === doc.customer_id &&
          r.row.store_id === actor.store_id,
      )
    )
      throw new ApiError(403, "Khách không thuộc cửa hàng.");
    const day = new Date(issued + 7 * 3600000)
      .toISOString()
      .slice(0, 10)
      .replaceAll("-", "");
    const prefix = `DH-${String(identities[0].results?.[0]?.code).replace(/^NT-/, "")}-${identities[1].results?.[0]?.code}-${day}-`;
    if (
      typeof doc.code !== "string" ||
      !doc.code.startsWith(prefix) ||
      !/^\d{3,}$/.test(doc.code.slice(prefix.length)) ||
      Number(doc.code.slice(prefix.length)) < 1
    )
      throw new ApiError(400, "Mã giữ hàng không khớp thiết bị/ngày.");
  }
  for (const r of records.filter((r) => r.table === "reservation_lines"))
    if (!ids.has(String(r.row.document_id)))
      throw new ApiError(400, "Dòng giữ thiếu DH.");
  const events = records
    .filter((r) => r.table === "reservation_events")
    .map((r) => r.row);
  if (events.length > 1)
    throw new ApiError(400, "Mỗi lần chỉ giải phóng/giao một phiếu giữ hàng.");
  for (const event of events) {
    if (!["release", "consume"].includes(String(event.kind)))
      throw new ApiError(400, "Loại giải phóng không hợp lệ.");
    checkPermission(
      actor.role,
      event.kind === "consume" ? "sell" : "reserve",
      actor.issued_role,
    );
    text(event.reason, "Lý do", 200);
    const instant = utcInstant(event.created_at, "Ngày giải phóng");
    if (
      instant > Date.now() + 300000 ||
      event.user_id !== actor.user_id ||
      event.store_id !== actor.store_id ||
      event.device_id !== actor.device_id
    )
      throw new ApiError(403, "Danh tính giải phóng không hợp lệ.");
    const rows = await db.batch<Record<string, unknown>>([
      db
        .prepare(
          "SELECT * FROM documents WHERE store_id=? AND device_id=? AND id=? AND type='DH' AND kind='reservation'",
        )
        .bind(actor.store_id, actor.device_id, event.document_id),
      db
        .prepare(
          "SELECT * FROM reservation_events WHERE store_id=? AND document_id=?",
        )
        .bind(actor.store_id, event.document_id),
      db
        .prepare(
          "SELECT variant_id,quantity FROM reservation_lines WHERE store_id=? AND document_id=?",
        )
        .bind(actor.store_id, event.document_id),
    ]);
    const dh = rows[0].results?.[0],
      previous = rows[1].results?.[0];
    if (
      !dh ||
      !rows[2].results?.length ||
      utcInstant(dh.issued_at, "Ngày giữ") > instant
    )
      throw new ApiError(403, "Phiếu giữ không thuộc máy hoặc sai ngày.");
    if (previous && previous.id !== event.id)
      throw new ApiError(409, "Phiếu đã giải phóng/giao.");
    if (event.kind === "release") {
      if (
        event.related_document_id !== null ||
        records.some(
          (r) => !["reservation_events", "audit_logs"].includes(r.table),
        )
      )
        throw new ApiError(400, "Giải phóng không được tạo nghiệp vụ khác.");
    } else {
      const hd = records.find(
        (r) =>
          r.table === "documents" && r.row.id === event.related_document_id,
      )?.row;
      if (
        !hd ||
        hd.type !== "HD" ||
        hd.kind !== "sale" ||
        hd.issued_at !== event.created_at ||
        hd.customer_id !== dh.customer_id ||
        metadata(hd).reservation_id !== dh.id ||
        reservationState(
          String(dh.issued_at),
          String(metadata(dh).expires_at),
          String(event.created_at),
        ) !== "active"
      )
        throw new ApiError(409, "HD giao hàng không khớp phiếu giữ còn hạn.");
      for (const held of rows[2].results ?? []) {
        const quantity = records
          .filter(
            (r) =>
              r.table === "invoice_lines" &&
              r.row.document_id === hd.id &&
              r.row.variant_id === held.variant_id,
          )
          .reduce((n, r) => n + Number(r.row.quantity), 0);
        if (!Number.isSafeInteger(quantity) || quantity < Number(held.quantity))
          throw new ApiError(400, "HD phải giao đủ hàng giữ.");
      }
    }
  }
  for (const hd of records.filter(
    (r) => r.table === "documents" && r.row.type === "HD",
  )) {
    const held = metadata(hd.row).reservation_id;
    if (
      held != null &&
      events.filter(
        (e) =>
          e.kind === "consume" &&
          e.document_id === held &&
          e.related_document_id === hd.row.id,
      ).length !== 1
    )
      throw new ApiError(400, "HD thiếu sự kiện giao hàng giữ.");
  }
  return ids;
}
