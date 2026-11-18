import type { Actor } from "./auth";
import type { Env } from "./index";
import { ApiError, checkPermission, text } from "./security";
import { auditStatement } from "./audit";
import {
  archiveSource,
  archiveLimits,
  verifyArchiveGzip,
  type AuditRow,
} from "./audit_archive_format";
type Row = Record<string, unknown>;
const uuid = (value: unknown) => {
  const id = text(value, "ID lô");
  if (
    !/^[a-f0-9]{8}-[a-f0-9]{4}-7[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(
      id,
    )
  )
    throw new ApiError(400, "Cần UUIDv7 do client sinh.");
  return id;
};
const owner = (actor: Actor) =>
  checkPermission(actor.role, "configure", actor.issued_role);
function scope(actor: Actor, store: string) {
  checkPermission(actor.role, "audit", actor.issued_role);
  if (
    store !== actor.store_id &&
    (actor.role !== "owner" || (actor.issued_role ?? actor.role) !== "owner")
  )
    throw new ApiError(403, "Không có quyền nhật ký cửa hàng khác.");
}
const objectKey = (row: Row) => `${row.object_key}/${row.gzip_hash}.json.gz`;
async function checkpoint(
  db: D1Database,
  store: unknown,
  device: unknown,
  direction: unknown,
) {
  return (
    (await db
      .prepare(
        "SELECT chain_index,hash FROM audit_chain_checkpoints WHERE store_id=? AND device_id=? AND direction=? ORDER BY upto DESC LIMIT 1",
      )
      .bind(store, device, direction)
      .first<{ chain_index: number; hash: string }>()) ?? {
      chain_index: 0,
      hash: "",
    }
  );
}
async function plan(db: D1Database, actor: Actor, id: string) {
  const row = await db
    .prepare("SELECT * FROM audit_archives WHERE id=?")
    .bind(id)
    .first<Row>();
  if (!row) throw new ApiError(404, "Không tìm thấy lô lưu trữ.");
  scope(actor, String(row.store_id));
  return row;
}
async function rowsFor(db: D1Database, row: Row) {
  return (
    await db
      .prepare(
        `SELECT * FROM audit_logs WHERE store_id=? AND device_id=? AND chain_index ${row.direction === 1 ? ">=" : "<="} ? AND chain_index ${row.direction === 1 ? "<=" : ">="} ? ORDER BY chain_index ${row.direction === 1 ? "ASC" : "DESC"}`,
      )
      .bind(row.store_id, row.device_id, row.first_index, row.last_index)
      .all<AuditRow>()
  ).results;
}
async function sourceFor(db: D1Database, row: Row) {
  const result = await archiveSource(
    {
      id: String(row.id),
      store_id: String(row.store_id),
      device_id: String(row.device_id),
      direction: row.direction as 1 | -1,
      previous_index: Number(row.previous_index),
      previous_hash: String(row.previous_hash),
      cutoff: String(row.cutoff),
    },
    await rowsFor(db, row),
  );
  if (
    result.source_hash !== row.source_hash ||
    result.bytes.length !== row.source_bytes ||
    result.receipts.length !== row.record_count
  )
    throw new ApiError(409, "Nguồn lô đã thay đổi hoặc thiếu; chưa xóa log.");
  return result;
}
function base64(bytes: Uint8Array) {
  let value = "";
  for (let i = 0; i < bytes.length; i += 8192)
    value += String.fromCharCode(...bytes.slice(i, i + 8192));
  return btoa(value);
}
async function readBounded(
  body: ReadableStream<Uint8Array> | null,
  limit: number,
) {
  if (!body) throw new ApiError(400, "Thiếu file gzip.");
  const reader = body.getReader(),
    chunks: Uint8Array[] = [];
  let count = 0;
  while (true) {
    const part = await reader.read();
    if (part.done) break;
    count += part.value.length;
    if (count > limit) {
      await reader.cancel();
      throw new ApiError(413, "File vượt giới hạn.");
    }
    chunks.push(part.value);
  }
  const bytes = new Uint8Array(count);
  let offset = 0;
  for (const part of chunks) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return bytes;
}
async function binaryHash(bytes: Uint8Array) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((v) => v.toString(16).padStart(2, "0"))
    .join("");
}
function bucket(env: Env) {
  if (!env.AUDIT_ARCHIVES)
    throw new ApiError(
      503,
      "Chưa cấu hình kho nhật ký R2 private. Log vẫn giữ trong D1.",
      "ARCHIVE_NOT_CONFIGURED",
    );
  return env.AUDIT_ARCHIVES;
}
async function verifiedObject(env: Env, row: Row) {
  const object = await bucket(env).get(objectKey(row));
  if (!object)
    throw new ApiError(409, "Thiếu file đã lưu trữ; không giảm log D1.");
  if (object.size !== row.gzip_bytes)
    throw new ApiError(409, "File lưu trữ sai kích thước.");
  const bytes = await readBounded(object.body, archiveLimits.compressedBytes);
  if ((await binaryHash(bytes)) !== row.gzip_hash)
    throw new ApiError(409, "File lưu trữ sai checksum.");
  await verifyArchiveGzip(
    bytes,
    String(row.source_hash),
    Number(row.source_bytes),
  );
  return bytes;
}
export async function archiveObject(
  env: Env,
  actor: Actor,
  id: string,
  request: Request,
) {
  const row = await plan(env.DB, actor, uuid(id));
  if (request.method === "GET") {
    if (!["verified", "committed"].includes(String(row.status)))
      throw new ApiError(409, "File chưa được xác minh.");
    const content = await verifiedObject(env, row);
    await env.DB.batch([
      await auditStatement(
        env.DB,
        actor,
        "AUDIT_ARCHIVE_DOWNLOAD",
        id,
        "Tải file nhật ký đã lưu trữ",
        { archive_id: id, store_id: row.store_id },
      ),
    ]);
    return new Response(content, {
      headers: {
        "Content-Type": "application/gzip",
        "Content-Disposition": `attachment; filename="audit-${id}.json.gz"`,
        "Cache-Control": "no-store",
      },
    });
  }
  owner(actor);
  bucket(env);
  if (!["prepared", "verified"].includes(String(row.status)))
    throw new ApiError(409, "Lô đã đóng.");
  const bytes = await readBounded(request.body, archiveLimits.compressedBytes),
    hash = await binaryHash(bytes);
  if (row.status === "verified" && hash !== row.gzip_hash)
    throw new ApiError(409, "Lô đã xác minh một file khác.");
  await verifyArchiveGzip(
    bytes,
    String(row.source_hash),
    Number(row.source_bytes),
  );
  await sourceFor(env.DB, row);
  const verified = { ...row, gzip_hash: hash, gzip_bytes: bytes.length };
  await bucket(env).put(objectKey(verified), bytes, {
    httpMetadata: { contentType: "application/gzip" },
    customMetadata: { source_hash: String(row.source_hash), gzip_hash: hash },
  });
  await verifiedObject(env, verified);
  if (row.status === "prepared")
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE audit_archives SET status='verified',gzip_hash=?,gzip_bytes=? WHERE id=? AND status='prepared'",
      ).bind(hash, bytes.length, id),
      await auditStatement(
        env.DB,
        actor,
        "AUDIT_ARCHIVE_VERIFY",
        id,
        "Xác minh file nhật ký private",
        {
          archive_id: id,
          store_id: row.store_id,
          record_count: row.record_count,
        },
      ),
    ]);
  return Response.json({ id, verified: true });
}
export async function auditArchives(
  env: Env,
  actor: Actor,
  url: URL,
  body?: Row,
) {
  if (!body) {
    const store = url.searchParams.get("store") ?? actor.store_id;
    scope(actor, store);
    const after = url.searchParams.get("cursor") ?? "";
    if (after.length > 200) throw new ApiError(400, "Cursor không hợp lệ.");
    const result = await env.DB.prepare(
      "SELECT * FROM audit_archives WHERE store_id=? AND id>? ORDER BY id LIMIT 51",
    )
      .bind(store, after)
      .all<Row>();
    const deviceCursor = url.searchParams.get("device_cursor") ?? "";
    if (deviceCursor.length > 200)
      throw new ApiError(400, "Cursor thiết bị không hợp lệ.");
    const devices = await env.DB.prepare(
      "SELECT id,code,name FROM devices WHERE store_id=? AND code>? ORDER BY code LIMIT 201",
    )
      .bind(store, deviceCursor)
      .all<Row>();
    const rows = result.results.slice(0, 50);
    return Response.json({
      rows,
      cursor: rows.at(-1)?.id ?? after,
      has_more: result.results.length > 50,
      devices: devices.results.slice(0, 200),
      more_devices: devices.results.length > 200,
      device_cursor: devices.results.slice(0, 200).at(-1)?.code ?? deviceCursor,
      enabled: !!env.AUDIT_ARCHIVES,
      retention_days: archiveLimits.retentionDays,
    });
  }
  owner(actor);
  const id = uuid(body.id);
  if (body.action === "prepare") {
    bucket(env);
    const store = text(body.store_id ?? actor.store_id, "Cửa hàng"),
      device = text(body.device_id, "Thiết bị");
    scope(actor, store);
    if (![1, -1].includes(Number(body.direction)))
      throw new ApiError(400, "Phía chain không hợp lệ.");
    const direction = Number(body.direction) as 1 | -1;
    if (
      !(await env.DB.prepare("SELECT 1 FROM devices WHERE store_id=? AND id=?")
        .bind(store, device)
        .first())
    )
      throw new ApiError(403, "Thiết bị khác cửa hàng.");
    const existing = await env.DB.prepare(
      "SELECT * FROM audit_archives WHERE id=?",
    )
      .bind(id)
      .first<Row>();
    if (existing) {
      if (
        existing.store_id !== store ||
        existing.device_id !== device ||
        existing.direction !== direction
      )
        throw new ApiError(409, "ID lô đã dùng với phạm vi khác.");
      if (!["prepared", "verified"].includes(String(existing.status)))
        return Response.json({ id, status: existing.status });
      const source = await sourceFor(env.DB, existing);
      return Response.json({
        manifest: existing,
        source_base64: base64(source.bytes),
      });
    }
    if (
      await env.DB.prepare(
        "SELECT id FROM audit_archives WHERE store_id=? AND device_id=? AND direction=? AND status IN ('prepared','verified')",
      )
        .bind(store, device, direction)
        .first()
    )
      throw new ApiError(
        409,
        "Chain này đang có lô chờ. Tiếp tục hoặc hủy lô đó trước.",
        "ARCHIVE_PENDING",
      );
    const previous = await checkpoint(env.DB, store, device, direction),
      cutoff = new Date(
        Date.now() - archiveLimits.retentionDays * 86400000,
      ).toISOString();
    const candidates = (
      await env.DB.prepare(
        `SELECT * FROM audit_logs WHERE store_id=? AND device_id=? AND chain_index ${direction === 1 ? ">" : "<"} ? ORDER BY chain_index ${direction === 1 ? "ASC" : "DESC"} LIMIT ?`,
      )
        .bind(store, device, previous.chain_index, archiveLimits.rows)
        .all<AuditRow>()
    ).results;
    const rows: AuditRow[] = [];
    let byteCount = 1000;
    for (const row of candidates) {
      if (
        typeof row.server_time !== "string" ||
        Date.parse(row.server_time) >= Date.parse(cutoff)
      )
        break;
      const size = new TextEncoder().encode(JSON.stringify(row)).length;
      if (byteCount + size > archiveLimits.sourceBytes) break;
      rows.push(row);
      byteCount += size;
    }
    if (!rows.length)
      throw new ApiError(
        409,
        "Đầu chain chưa hết thời gian giữ hoặc log vượt giới hạn; chưa giảm dữ liệu D1.",
        "ARCHIVE_NOT_READY",
      );
    const source = await archiveSource(
      {
        id,
        store_id: store,
        device_id: device,
        direction,
        previous_index: previous.chain_index,
        previous_hash: previous.hash,
        cutoff,
      },
      rows,
    );
    const created = new Date().toISOString(),
      key = `audit/${encodeURIComponent(store)}/${encodeURIComponent(device)}/${direction === 1 ? "client" : "api"}/${id}`;
    await env.DB.batch([
      env.DB.prepare(
        "INSERT INTO audit_archives VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'prepared',NULL,NULL,?,NULL)",
      ).bind(
        id,
        store,
        device,
        direction,
        source.first_index,
        source.last_index,
        previous.chain_index,
        previous.hash,
        source.last_hash,
        source.source_hash,
        source.bytes.length,
        rows.length,
        cutoff,
        actor.user_id,
        key,
        created,
      ),
      await auditStatement(
        env.DB,
        actor,
        "AUDIT_ARCHIVE_PREPARE",
        id,
        "Chuẩn bị lưu trữ nhật ký cũ",
        { archive_id: id, store_id: store, record_count: rows.length },
      ),
    ]);
    return Response.json({
      manifest: await plan(env.DB, actor, id),
      source_base64: base64(source.bytes),
    });
  }
  const row = await plan(env.DB, actor, id);
  if (body.action === "cancel") {
    if (row.status === "cancelled")
      return Response.json({ id, cancelled: true });
    if (!["prepared", "verified"].includes(String(row.status)))
      throw new ApiError(409, "Lô đã hoàn tất.");
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE audit_archives SET status='cancelled' WHERE id=? AND status IN ('prepared','verified')",
      ).bind(id),
      await auditStatement(
        env.DB,
        actor,
        "AUDIT_ARCHIVE_CANCEL",
        id,
        text(body.reason, "Lý do", 200),
        { archive_id: id },
      ),
    ]);
    return Response.json({ id, cancelled: true });
  }
  if (body.action !== "commit" || body.confirmed !== true)
    throw new ApiError(400, "Cần xác nhận lưu trữ lô đã kiểm chứng.");
  if (row.status === "committed") return Response.json({ id, committed: true });
  if (row.status !== "verified")
    throw new ApiError(409, "Chưa xác minh file trên R2; log giữ nguyên.");
  await verifiedObject(env, row);
  const source = await sourceFor(env.DB, row),
    now = new Date().toISOString();
  const guard = env.DB.prepare(
    "INSERT INTO audit_archive_guards VALUES(?,?,?,CASE WHEN EXISTS(SELECT 1 FROM audit_archives WHERE id=? AND status='verified' AND gzip_hash=?) AND COALESCE((SELECT upto FROM audit_chain_checkpoints WHERE store_id=? AND device_id=? AND direction=? ORDER BY upto DESC LIMIT 1),0)=? AND (SELECT COUNT(*) FROM audit_logs WHERE store_id=? AND device_id=? AND chain_index BETWEEN ? AND ?)=? THEN 1 ELSE 0 END)",
  ).bind(
    id,
    row.store_id,
    id,
    id,
    row.gzip_hash,
    row.store_id,
    row.device_id,
    row.direction,
    Math.abs(Number(row.previous_index)),
    row.store_id,
    row.device_id,
    Math.min(Number(row.first_index), Number(row.last_index)),
    Math.max(Number(row.first_index), Number(row.last_index)),
    row.record_count,
  );
  await env.DB.batch([
    guard,
    ...source.receipts.map((r) =>
      env.DB.prepare(
        "INSERT INTO audit_archive_receipts VALUES(?,?,?,?,?,?)",
      ).bind(
        r.id,
        row.store_id,
        row.device_id,
        id,
        r.chain_index,
        r.record_digest,
      ),
    ),
    env.DB.prepare(
      "INSERT INTO audit_chain_checkpoints VALUES(?,?,?,?,?,?,?,?)",
    ).bind(
      id,
      row.store_id,
      row.device_id,
      row.direction,
      Math.abs(Number(row.last_index)),
      row.last_index,
      row.last_hash,
      now,
    ),
    env.DB.prepare(
      "DELETE FROM audit_logs WHERE store_id=? AND device_id=? AND chain_index BETWEEN ? AND ?",
    ).bind(
      row.store_id,
      row.device_id,
      Math.min(Number(row.first_index), Number(row.last_index)),
      Math.max(Number(row.first_index), Number(row.last_index)),
    ),
    env.DB.prepare(
      "DELETE FROM change_feed WHERE store_id=? AND entity_type='audit_logs' AND entity_id IN (SELECT id FROM audit_archive_receipts WHERE store_id=? AND archive_id=?)",
    ).bind(row.store_id, row.store_id, id),
    env.DB.prepare(
      "UPDATE audit_archives SET status='committed',committed_at=? WHERE id=? AND status='verified'",
    ).bind(now, id),
    env.DB.prepare("DELETE FROM audit_archive_guards WHERE id=?").bind(id),
    await auditStatement(
      env.DB,
      actor,
      "AUDIT_ARCHIVE_COMMIT",
      id,
      "Chuyển log cũ sang file private đã kiểm chứng",
      {
        archive_id: id,
        record_count: row.record_count,
        source_hash: row.source_hash,
      },
    ),
  ]);
  return Response.json({ id, committed: true });
}
