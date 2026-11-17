import type { Actor } from "./auth";
import type { SyncRecord } from "./sync";
import { ApiError, checkPermission, text, money } from "./security";
import { utcInstant } from "./reservation_time";
type Row = Record<string, unknown>;
type Item = {
  variant_id: string;
  quantity: number;
  name: string;
  size: string;
  color: string;
  unit: string;
  unit_cost: number;
  price_version: string;
};
function object(value: unknown): Row {
  try {
    const result: unknown = JSON.parse(String(value));
    if (!result || typeof result !== "object" || Array.isArray(result))
      throw new Error();
    return result as Row;
  } catch {
    throw new ApiError(400, "Thông tin chuyển kho không hợp lệ.");
  }
}
function items(value: unknown): Item[] {
  try {
    const result: unknown = JSON.parse(String(value));
    if (!Array.isArray(result) || result.length < 1 || result.length > 20)
      throw new Error();
    return result as Item[];
  } catch {
    throw new ApiError(400, "Danh sách chuyển kho không hợp lệ.");
  }
}
function scope(row: Row, actor: Actor) {
  if (
    row.store_id !== actor.store_id ||
    row.device_id !== actor.device_id ||
    row.user_id !== actor.user_id
  )
    throw new ApiError(403, "Chuyển kho sai người, cửa hàng hoặc thiết bị.");
}
function instant(value: unknown): number {
  const time = utcInstant(value, "Thời điểm chuyển kho");
  if (time > Date.now() + 300000)
    throw new ApiError(409, "Đồng hồ thiết bị sai.", "CLOCK_SKEW");
  return time;
}
function project(
  db: D1Database,
  mutationId: string,
  table: string,
  row: Row,
): D1PreparedStatement[] {
  const columns = Object.keys(row);
  return [
    db
      .prepare(
        `INSERT INTO ${table} (${columns.join(",")}) VALUES (${columns.map(() => "?").join(",")})`,
      )
      .bind(...Object.values(row)),
    db
      .prepare(
        "INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) VALUES(?,?,?,?,?,?)",
      )
      .bind(
        row.store_id,
        mutationId,
        table,
        row.id,
        JSON.stringify(row),
        new Date().toISOString(),
      ),
  ];
}
export async function validateTransfers(
  db: D1Database,
  actor: Actor,
  records: SyncRecord[],
  mutationId: string,
): Promise<{ ids: Set<string>; projections: D1PreparedStatement[] }> {
  const docs = records
      .filter((r) => r.table === "documents" && r.row.type === "CK")
      .map((r) => r.row),
    events = records
      .filter((r) => r.table === "transfer_events")
      .map((r) => r.row),
    receipts = records
      .filter((r) => r.table === "transfer_receipts")
      .map((r) => r.row);
  const ids = new Set<string>(),
    projections: D1PreparedStatement[] = [];
  if (!docs.length && !events.length && !receipts.length)
    return { ids, projections };
  checkPermission(actor.role, "stock", actor.issued_role);
  if (
    docs.length > 1 ||
    events.length > 1 ||
    receipts.length > 1 ||
    (docs.length && records.filter((r) => r.table === "documents").length !== 1)
  )
    throw new ApiError(400, "Mỗi mutation chỉ một phiếu chuyển kho.");
  for (const doc of docs) {
    scope(doc, actor);
    const id = text(doc.id, "Phiếu CK"),
      time = instant(doc.issued_at),
      meta = object(doc.metadata_json);
    text(doc.school_year, "Năm học");
    ids.add(id);
    if (
      !["transfer_out", "transfer_in"].includes(String(doc.kind)) ||
      doc.customer_id !== null ||
      doc.original_id !== null ||
      money(doc.total) !== 0 ||
      doc.subtotal !== 0 ||
      doc.discount !== 0
    )
      throw new ApiError(
        400,
        "Phiếu CK không được có doanh thu, khách hoặc công nợ.",
      );
    if (
      records.some(
        (r) =>
          ![
            "documents",
            "invoice_lines",
            "stock_movements",
            "transfer_receipts",
            "audit_logs",
          ].includes(r.table) ||
          (["invoice_lines", "stock_movements"].includes(r.table) &&
            r.row.document_id !== id),
      )
    )
      throw new ApiError(400, "CK chỉ gồm dòng hàng và sổ cái kho tương ứng.");
    const identities = await db.batch<Row>([
      db.prepare("SELECT code FROM stores WHERE id=?").bind(actor.store_id),
      db
        .prepare("SELECT code FROM devices WHERE store_id=? AND id=?")
        .bind(actor.store_id, actor.device_id),
    ]);
    const day = new Date(time + 7 * 3600000)
        .toISOString()
        .slice(0, 10)
        .replaceAll("-", ""),
      prefix = `CK-${String(identities[0].results?.[0]?.code).replace(/^NT-/, "")}-${identities[1].results?.[0]?.code}-${day}-`;
    if (
      typeof doc.code !== "string" ||
      !doc.code.startsWith(prefix) ||
      !/^\d{3,}$/.test(doc.code.slice(prefix.length)) ||
      Number(doc.code.slice(prefix.length)) < 1
    )
      throw new ApiError(400, "Mã CK không khớp chi nhánh/máy/ngày.");
    const lines = records
        .filter((r) => r.table === "invoice_lines")
        .map((r) => r.row),
      movements = records
        .filter((r) => r.table === "stock_movements")
        .map((r) => r.row);
    let expected: Item[];
    if (doc.kind === "transfer_out") {
      if (
        !lines.length ||
        lines.length > 20 ||
        receipts.length ||
        meta.target_store_id === actor.store_id
      )
        throw new ApiError(
          400,
          "Phiếu xuất cần 1–20 biến thể và cửa hàng nhận khác.",
        );
      const target = await db
        .prepare(
          "SELECT d.code AS device_code,s.code AS store_code FROM devices d JOIN stores s ON s.id=d.store_id WHERE d.store_id=? AND d.id=? AND d.status='approved' AND s.active=1",
        )
        .bind(
          text(meta.target_store_id, "Cửa hàng nhận"),
          text(meta.target_device_id, "Máy nhận"),
        )
        .first<Row>();
      if (
        !target ||
        target.store_code !== meta.target_store_code ||
        target.device_code !== meta.target_device_code
      )
        throw new ApiError(
          409,
          "Máy nhận chưa duyệt hoặc thông tin điểm nhận thay đổi.",
        );
      text(meta.notes, "Lý do chuyển", 1000);
      const versions = await db.batch<Row>(
        lines.map((l) =>
          db
            .prepare(
              "SELECT cost FROM variant_price_history WHERE variant_id=? AND version=?",
            )
            .bind(l.variant_id, l.price_version),
        ),
      );
      expected = lines.map((line, index) => {
        if (
          !versions[index].results?.[0] ||
          versions[index].results[0].cost !== line.unit_cost
        )
          throw new ApiError(
            409,
            "Giá vốn chuyển kho không khớp revision.",
            "PRICE_VERSION",
          );
        return {
          variant_id: text(line.variant_id, "Biến thể"),
          quantity: Number(line.quantity),
          name: String(line.name),
          size: String(line.size),
          color: String(line.color),
          unit: String(line.unit),
          unit_cost: money(line.unit_cost),
          price_version: String(line.price_version),
        };
      });
    } else {
      const receipt = receipts[0];
      if (
        !receipt ||
        receipt.id !== id ||
        receipt.created_at !== doc.issued_at ||
        receipt.offer_id !== meta.offer_id
      )
        throw new ApiError(400, "Phiếu nhận thiếu biên nhận tương ứng.");
      scope(receipt, actor);
      text(receipt.reason, "Lý do nhận/chênh lệch", 200);
      const lookup = await db.batch<Row>([
        db
          .prepare(
            "SELECT * FROM transfer_offers WHERE store_id=? AND device_id=? AND id=?",
          )
          .bind(
            actor.store_id,
            actor.device_id,
            text(receipt.offer_id, "Phiếu đang chuyển"),
          ),
        db
          .prepare(
            "SELECT id FROM transfer_receipts WHERE store_id=? AND offer_id=?",
          )
          .bind(actor.store_id, receipt.offer_id),
      ]);
      const offer = lookup[0].results?.[0],
        previous = lookup[1].results?.[0];
      if (
        !offer ||
        String(offer.dispatched_at) > String(doc.issued_at) ||
        (previous && previous.id !== id)
      )
        throw new ApiError(
          409,
          "Phiếu đã nhận, chưa chuyển hoặc không thuộc máy nhận.",
        );
      if (doc.school_year !== offer.school_year)
        throw new ApiError(400, "Năm học phiếu nhận không khớp phiếu xuất.");
      const sent = items(offer.items_json);
      let counts: Row[];
      try {
        const value: unknown = JSON.parse(String(receipt.counts_json));
        if (!Array.isArray(value)) throw new Error();
        counts = value as Row[];
      } catch {
        throw new ApiError(400, "Số thực nhận không hợp lệ.");
      }
      const seen = new Set<string>();
      if (counts.length !== sent.length)
        throw new ApiError(400, "Cần ghi thực nhận mọi biến thể, kể cả 0.");
      for (const c of counts) {
        if (!c || typeof c !== "object" || Array.isArray(c))
          throw new ApiError(400, "Dòng thực nhận không hợp lệ.");
        const variant = text(c.variant_id, "Biến thể");
        if (
          Object.keys(c).length !== 2 ||
          seen.has(variant) ||
          !sent.some((i) => i.variant_id === variant) ||
          !Number.isSafeInteger(c.quantity) ||
          Number(c.quantity) < 0 ||
          Number(c.quantity) > 100000
        )
          throw new ApiError(400, "Số thực nhận hoặc biến thể không hợp lệ.");
        seen.add(variant);
      }
      expected = sent
        .map((i) => ({
          ...i,
          quantity: Number(
            counts.find((c) => c.variant_id === i.variant_id)!.quantity,
          ),
        }))
        .filter((i) => i.quantity > 0);
      if (!previous) {
        const delivery: Row = {
          id,
          store_id: offer.source_store_id,
          document_id: offer.id,
          received_store_id: actor.store_id,
          received_device_id: actor.device_id,
          receipt_code: doc.code,
          counts_json: receipt.counts_json,
          reason: receipt.reason,
          user_id: actor.user_id,
          receiver_name: actor.name,
          created_at: doc.issued_at,
        };
        projections.push(
          ...project(db, mutationId, "transfer_deliveries", delivery),
        );
      }
    }
    const seen = new Set<string>();
    if (
      lines.length !== expected.length ||
      movements.length !== expected.length
    )
      throw new ApiError(
        400,
        "Dòng CK và biến động kho không khớp thực nhận/xuất.",
      );
    for (const item of expected) {
      if (
        seen.has(item.variant_id) ||
        !Number.isSafeInteger(item.quantity) ||
        item.quantity < 1 ||
        item.quantity > 100000
      )
        throw new ApiError(
          400,
          "Biến thể trùng hoặc lượng chuyển không hợp lệ.",
        );
      seen.add(item.variant_id);
      const line = lines.find((l) => l.variant_id === item.variant_id),
        movement = movements.find((m) => m.variant_id === item.variant_id);
      if (
        !line ||
        !movement ||
        line.quantity !== item.quantity ||
        line.unit_price !== 0 ||
        line.discount !== 0 ||
        line.unit_cost !== item.unit_cost ||
        line.price_version !== item.price_version ||
        ["name", "size", "color", "unit"].some(
          (k) => line[k] !== item[k as keyof Item],
        )
      )
        throw new ApiError(400, "Snapshot hoặc số lượng CK không khớp.");
      scope(movement, actor);
      text(movement.reason, "Lý do kho");
      if (
        movement.kind !== doc.kind ||
        movement.quantity !==
          (doc.kind === "transfer_out" ? -item.quantity : item.quantity) ||
        movement.created_at !== doc.issued_at
      )
        throw new ApiError(400, "Xuất/nhập CK không khớp phiếu.");
    }
  }
  if (receipts.some((r) => !ids.has(String(r.id))))
    throw new ApiError(400, "Biên nhận phải cùng CK nhận.");
  for (const event of events) {
    if (
      records.some((r) => !["transfer_events", "audit_logs"].includes(r.table))
    )
      throw new ApiError(
        400,
        "Chuyển trạng thái không được kèm nghiệp vụ khác.",
      );
    scope(event, actor);
    instant(event.created_at);
    text(event.reason, "Lý do chuyển", 200);
    const lookup = await db.batch<Row>([
      db
        .prepare(
          "SELECT * FROM documents WHERE store_id=? AND device_id=? AND id=? AND type='CK' AND kind='transfer_out'",
        )
        .bind(
          actor.store_id,
          actor.device_id,
          text(event.document_id, "Phiếu xuất"),
        ),
      db
        .prepare(
          "SELECT id FROM transfer_events WHERE store_id=? AND document_id=?",
        )
        .bind(actor.store_id, event.document_id),
    ]);
    const doc = lookup[0].results?.[0],
      previous = lookup[1].results?.[0];
    if (
      !doc ||
      String(doc.issued_at) > String(event.created_at) ||
      (previous && previous.id !== event.id)
    )
      throw new ApiError(409, "Phiếu không thuộc máy hoặc đã chuyển.");
    if (!previous) {
      const meta = object(doc.metadata_json);
      const target = await db
        .prepare(
          "SELECT d.id FROM devices d JOIN stores s ON s.id=d.store_id WHERE d.store_id=? AND d.id=? AND d.status='approved' AND s.active=1",
        )
        .bind(meta.target_store_id, meta.target_device_id)
        .first();
      if (!target)
        throw new ApiError(
          409,
          "Máy nhận đã bị thu hồi; cần đối soát trước khi chuyển.",
        );
      const result = await db
        .prepare(
          "SELECT variant_id,quantity,name,size,color,unit,unit_cost,price_version FROM invoice_lines WHERE store_id=? AND document_id=?",
        )
        .bind(actor.store_id, doc.id)
        .all();
      const offer: Row = {
        id: doc.id,
        store_id: meta.target_store_id,
        device_id: meta.target_device_id,
        source_store_id: actor.store_id,
        source_device_id: actor.device_id,
        source_code: doc.code,
        source_store_code: "NT-" + String(doc.code).split("-")[1],
        source_device_code: String(doc.code).split("-")[2],
        issued_at: doc.issued_at,
        dispatched_at: event.created_at,
        school_year: doc.school_year,
        items_json: JSON.stringify(result.results),
        notes: meta.notes,
      };
      projections.push(...project(db, mutationId, "transfer_offers", offer));
    }
  }
  return { ids, projections };
}
