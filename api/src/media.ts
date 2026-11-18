import type { Actor } from "./auth";
import type { Env } from "./index";
import { auditStatement } from "./audit";
import { ApiError, checkPermission, sha256 } from "./security";
const maxBytes = 204800;
export function jpegDimensions(data: Uint8Array): [number, number] {
  if (data.length < 4 || data[0] !== 255 || data[1] !== 216)
    throw new ApiError(400, "Ảnh sản phẩm phải là JPEG đã nén.");
  let i = 2;
  while (i + 3 < data.length) {
    if (data[i++] !== 255) throw new ApiError(400, "JPEG không hợp lệ.");
    while (data[i] === 255) i++;
    const marker = data[i++];
    if (marker === 217 || marker === 218) break;
    if (marker === 1 || (marker >= 208 && marker <= 215)) continue;
    const length = (data[i] << 8) | data[i + 1];
    if (length < 2 || i + length > data.length) break;
    if ([192, 193, 194].includes(marker)) {
      if (length < 8) break;
      const h = (data[i + 3] << 8) | data[i + 4],
        w = (data[i + 5] << 8) | data[i + 6];
      if (
        w < 1 ||
        h < 1 ||
        w > 1024 ||
        h > 1024 ||
        data[data.length - 2] !== 255 ||
        data[data.length - 1] !== 217
      )
        break;
      return [w, h];
    }
    i += length;
  }
  throw new ApiError(
    400,
    "Kích thước/định dạng JPEG không hợp lệ (tối đa 1024×1024).",
  );
}
async function readImage(request: Request) {
  if (Number(request.headers.get("Content-Length")) > maxBytes)
    throw new ApiError(413, "Ảnh vượt 200KB.");
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError(400, "Thiếu ảnh.");
  const parts: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const r = await reader.read();
      if (r.done) break;
      length += r.value.length;
      if (length > maxBytes) {
        await reader.cancel();
        throw new ApiError(413, "Ảnh vượt 200KB.");
      }
      parts.push(r.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const p of parts) {
    bytes.set(p, offset);
    offset += p.length;
  }
  return bytes;
}
export async function media(
  env: Env,
  actor: Actor,
  request: Request,
  hash: string,
): Promise<Response> {
  if (!/^[a-f0-9]{64}$/.test(hash))
    throw new ApiError(400, "Mã ảnh không hợp lệ.");
  if (!env.IMAGES)
    throw new ApiError(
      503,
      "Cloud chưa bật kho ảnh. Ảnh vẫn được lưu trên máy và trong sao lưu cục bộ.",
      "MEDIA_NOT_CONFIGURED",
    );
  const key = `products/${hash}.jpg`;
  if (request.method === "GET") {
    if (
      !(await env.DB.prepare("SELECT id FROM media_objects WHERE id=?")
        .bind(hash)
        .first())
    )
      throw new ApiError(404, "Ảnh chưa đồng bộ.", "MEDIA_PENDING");
    const object = await env.IMAGES.get(key);
    if (!object)
      throw new ApiError(
        404,
        "Không tìm thấy ảnh trên cloud.",
        "MEDIA_MISSING",
      );
    return new Response(object.body, {
      headers: {
        "Content-Type": "image/jpeg",
        "Content-Length": String(object.size),
        ETag: `"${hash}"`,
      },
    });
  }
  checkPermission(actor.role, "catalog", actor.issued_role);
  const id = request.headers.get("X-Mutation-ID");
  if (
    !id ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      id,
    )
  )
    throw new ApiError(400, "ID ảnh phải do client sinh.");
  const bytes = await readImage(request);
  jpegDimensions(bytes);
  const actual = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
  if (actual !== hash) throw new ApiError(400, "Checksum ảnh không khớp.");
  const recordHash = await sha256(
    JSON.stringify({ actor: actor.user_id, device: actor.device_id, hash }),
  );
  const previous = await env.DB.prepare(
    "SELECT payload_hash FROM processed_mutations WHERE store_id=? AND id=?",
  )
    .bind(actor.store_id, id)
    .first<{ payload_hash: string }>();
  if (previous) {
    if (previous.payload_hash !== recordHash)
      throw new ApiError(409, "ID ảnh đã dùng cho nội dung khác.");
    return Response.json({ ok: true, id, hash });
  }
  // R2 precedes the D1 receipt. A failed D1 transaction is safe to retry: the
  // same immutable content hash writes the same bytes, never another image.
  await env.IMAGES.put(key, bytes, {
    httpMetadata: { contentType: "image/jpeg" },
  });
  const now = new Date().toISOString();
  try {
    await env.DB.batch([
      env.DB.prepare(
        "INSERT OR IGNORE INTO media_objects VALUES(?,?,?,?)",
      ).bind(hash, "image/jpeg", bytes.length, now),
      env.DB.prepare(
        "INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) SELECT '*',?,'media_objects',id,json_object('id',id,'mime',mime,'byte_count',byte_count,'created_at',created_at),? FROM media_objects WHERE id=?",
      ).bind(id, now, hash),
      await auditStatement(
        env.DB,
        actor,
        "PRODUCT_IMAGE_UPLOAD",
        hash,
        "Đồng bộ ảnh sản phẩm",
        { hash, bytes: bytes.length },
      ),
      env.DB.prepare("INSERT INTO processed_mutations VALUES(?,?,?,?,?)").bind(
        actor.store_id,
        id,
        actor.device_id,
        recordHash,
        now,
      ),
    ]);
  } catch (error) {
    const saved = await env.DB.prepare(
      "SELECT payload_hash FROM processed_mutations WHERE store_id=? AND id=?",
    )
      .bind(actor.store_id, id)
      .first<{ payload_hash: string }>();
    if (saved?.payload_hash !== recordHash) throw error;
  }
  return Response.json({ ok: true, id, hash });
}
