import { ApiError, sha256 } from "./security";
export type AuditRow = Record<string, unknown>;
export const archiveLimits = {
  rows: 20,
  sourceBytes: 192000,
  compressedBytes: 194000,
  retentionDays: 90,
} as const;
const columns = [
  "id",
  "store_id",
  "device_id",
  "user_id",
  "role",
  "action",
  "entity_type",
  "entity_id",
  "document_code",
  "changes_json",
  "reason",
  "client_time",
  "server_time",
  "app_version",
  "severity",
  "hash_prev",
  "hash",
  "chain_index",
] as const;
export async function auditRecordDigest(row: AuditRow) {
  return sha256(
    JSON.stringify(
      Object.fromEntries(
        columns.filter((c) => c !== "server_time").map((c) => [c, row[c]]),
      ),
    ),
  );
}
export async function verifyAuditHash(row: AuditRow) {
  let changes: unknown;
  try {
    changes = JSON.parse(String(row.changes_json));
  } catch {
    throw new ApiError(409, "JSON nhật ký hỏng.");
  }
  const canonical = {
    id: row.id,
    store_id: row.store_id,
    device_id: row.device_id,
    user_id: row.user_id,
    role: row.role,
    action: row.action,
    entity_type: row.entity_type,
    entity_id: row.entity_id,
    changes,
    reason: row.reason,
    client_time: row.client_time,
    severity: row.severity,
    hash_prev: row.hash_prev,
    chain_index: row.chain_index,
  };
  if ((await sha256(JSON.stringify(canonical))) !== row.hash)
    throw new ApiError(
      409,
      "Nhật ký sai checksum; chưa được lưu trữ.",
      "AUDIT_HASH",
    );
}
export async function archiveSource(
  input: {
    id: string;
    store_id: string;
    device_id: string;
    direction: 1 | -1;
    previous_index: number;
    previous_hash: string;
    cutoff: string;
  },
  rows: AuditRow[],
) {
  if (!rows.length || rows.length > archiveLimits.rows)
    throw new ApiError(400, "Số log trong lô không hợp lệ.");
  let index = input.previous_index,
    hash = input.previous_hash;
  const receipts: {
    id: unknown;
    chain_index: number;
    record_digest: string;
  }[] = [];
  for (const row of rows) {
    index += input.direction;
    if (
      row.store_id !== input.store_id ||
      row.device_id !== input.device_id ||
      row.chain_index !== index ||
      row.hash_prev !== hash
    )
      throw new ApiError(409, "Chain lưu trữ không liên tục.");
    if (
      typeof row.server_time !== "string" ||
      !Number.isFinite(Date.parse(row.server_time)) ||
      Date.parse(row.server_time) >= Date.parse(input.cutoff)
    )
      throw new ApiError(409, "Chưa hết thời gian giữ nhật ký trên cloud.");
    await verifyAuditHash(row);
    hash = String(row.hash);
    receipts.push({
      id: row.id,
      chain_index: index,
      record_digest: await auditRecordDigest(row),
    });
  }
  const source = JSON.stringify({
    format: 1,
    ...input,
    rows: rows.map((row) =>
      Object.fromEntries(columns.map((c) => [c, row[c]])),
    ),
  });
  const bytes = new TextEncoder().encode(source);
  if (bytes.length > archiveLimits.sourceBytes)
    throw new ApiError(
      413,
      "Lô log quá lớn; cần giảm số log. Dữ liệu chưa bị xóa.",
    );
  return {
    source,
    bytes,
    source_hash: await sha256(source),
    first_index: input.previous_index + input.direction,
    last_index: index,
    last_hash: hash,
    receipts,
  };
}
export async function verifyArchiveGzip(
  compressed: Uint8Array,
  expectedHash: string,
  expectedBytes: number,
) {
  if (
    compressed.length > archiveLimits.compressedBytes ||
    !Number.isSafeInteger(expectedBytes) ||
    expectedBytes < 1 ||
    expectedBytes > archiveLimits.sourceBytes
  )
    throw new ApiError(413, "File lưu trữ quá lớn.");
  const stream = new Response(compressed).body!.pipeThrough(
    new DecompressionStream("gzip"),
  );
  const reader = stream.getReader();
  let count = 0;
  const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      count += chunk.value.length;
      if (count > expectedBytes) {
        await reader.cancel();
        throw new ApiError(400, "File giải nén vượt nguồn đã chuẩn bị.");
      }
      chunks.push(chunk.value);
    }
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, "File gzip hỏng.");
  }
  const bytes = new Uint8Array(count);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(
      bytes,
    );
  } catch {
    throw new ApiError(400, "File nguồn không phải UTF-8.");
  }
  if (count !== expectedBytes || (await sha256(text)) !== expectedHash)
    throw new ApiError(409, "Checksum file khác nguồn đã chuẩn bị.");
  return text;
}
