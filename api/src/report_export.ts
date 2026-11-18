import type { Actor } from "./auth";
import { auditStatement } from "./audit";
import { ApiError, checkPermission, sha256, text } from "./security";

// Ghi yêu cầu xuất trước khi trình duyệt tải file; không khẳng định đã lưu file.
export async function reportExport(
  db: D1Database,
  actor: Actor,
  body: Record<string, unknown>,
): Promise<Response> {
  checkPermission(actor.role, "reports", actor.issued_role);
  const id = text(body.id, "ID yêu cầu"),
    name = text(body.name, "Tên báo cáo", 1000),
    format = body.format;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      id,
    ) ||
    !["PDF", "XLSX"].includes(String(format))
  )
    throw new ApiError(400, "Yêu cầu xuất không hợp lệ.");
  const hash = await sha256(
    JSON.stringify({
      user: actor.user_id,
      device: actor.device_id,
      name,
      format,
    }),
  );
  const existing = await db
    .prepare(
      "SELECT payload_hash FROM processed_mutations WHERE store_id=? AND id=?",
    )
    .bind(actor.store_id, id)
    .first<{ payload_hash: string }>();
  if (existing) {
    if (existing.payload_hash !== hash)
      throw new ApiError(409, "ID yêu cầu đã dùng cho nội dung khác.");
    return Response.json({ ok: true });
  }
  const statements = [
    db
      .prepare("INSERT INTO processed_mutations VALUES(?,?,?,?,?)")
      .bind(
        actor.store_id,
        id,
        actor.device_id,
        hash,
        new Date().toISOString(),
      ),
    await auditStatement(
      db,
      actor,
      "REPORT_EXPORT_REQUEST",
      id,
      "Yêu cầu tải báo cáo online",
      { name, format },
    ),
  ];
  try {
    await db.batch(statements);
  } catch (error) {
    const saved = await db
      .prepare(
        "SELECT payload_hash FROM processed_mutations WHERE store_id=? AND id=?",
      )
      .bind(actor.store_id, id)
      .first<{ payload_hash: string }>();
    if (saved?.payload_hash !== hash) throw error;
  }
  return Response.json({ ok: true });
}
