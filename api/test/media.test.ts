import { readFileSync } from "node:fs";
import { it, expect } from "vitest";
import { media, jpegDimensions } from "../src/media";
import { fixture, actor } from "./report_fixtures";
import type { Env } from "../src/index";
const bytes = new Uint8Array(
  readFileSync("../docs/test-vectors/product-photo.jpg"),
);
async function hash(data: Uint8Array) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(data))),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
}
const id = "019a1234-0000-7000-8000-000000000055";
const upload = (data = bytes) =>
  new Request("https://fixture/media/image", {
    method: "PUT",
    headers: { "X-Mutation-ID": id, "Content-Type": "image/jpeg" },
    body: new Uint8Array(data),
  });
function storage() {
  const objects = new Map<string, Uint8Array>();
  let writes = 0;
  return {
    objects,
    get writes() {
      return writes;
    },
    bucket: {
      put: async (key: string, data: Uint8Array) => {
        writes++;
        objects.set(key, new Uint8Array(data));
      },
      get: async (key: string) => {
        const data = objects.get(key);
        return data
          ? {
              size: data.length,
              body: new ReadableStream({
                start(c) {
                  c.enqueue(data);
                  c.close();
                },
              }),
            }
          : null;
      },
    },
  };
}
it("Ảnh có checksum/idempotency, metadata/feed/audit/ACK nguyên tử, download đúng byte", async () => {
  const { db, sqlite } = fixture(),
    s = storage(),
    env = { DB: db, IMAGES: s.bucket } as unknown as Env;
  try {
    const digest = await hash(bytes);
    expect(jpegDimensions(bytes)).toEqual([32, 16]);
    await media(env, actor, upload(), digest);
    await media(env, actor, upload(), digest);
    expect(s.writes).toBe(1);
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM media_objects").get()?.n,
    ).toBe(1);
    expect(
      sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM audit_logs WHERE action='PRODUCT_IMAGE_UPLOAD'",
        )
        .get()?.n,
    ).toBe(1);
    expect(
      sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM change_feed WHERE entity_type='media_objects'",
        )
        .get()?.n,
    ).toBe(1);
    const result = await media(
      env,
      actor,
      new Request("https://fixture/media/image"),
      digest,
    );
    expect(new Uint8Array(await result.arrayBuffer())).toEqual(bytes);
    expect(result.headers.get("Content-Type")).toBe("image/jpeg");
    const changed = new Uint8Array(bytes);
    changed[15] ^= 1;
    await expect(
      media(env, actor, upload(changed), await hash(changed)),
    ).rejects.toThrow(/ID/);
  } finally {
    sqlite.close();
  }
});
it("Từ chối sai quyền/checksum/ảnh lớn; R2 chưa bật trả mã riêng, không ACK ảnh giả", async () => {
  const { db, sqlite } = fixture(),
    s = storage(),
    env = { DB: db, IMAGES: s.bucket } as unknown as Env;
  try {
    const digest = await hash(bytes);
    await expect(
      media({ ...env, IMAGES: undefined }, actor, upload(), digest),
    ).rejects.toMatchObject({ code: "MEDIA_NOT_CONFIGURED" });
    await expect(
      media(env, { ...actor, role: "cashier" }, upload(), digest),
    ).rejects.toThrow();
    await expect(
      media(env, { ...actor, issued_role: "cashier" }, upload(), digest),
    ).rejects.toThrow();
    await expect(media(env, actor, upload(), "0".repeat(64))).rejects.toThrow(
      /Checksum/,
    );
    await expect(
      media(env, actor, upload(new Uint8Array(204801)), digest),
    ).rejects.toMatchObject({ status: 413 });
    expect(s.writes).toBe(0);
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM processed_mutations").get()?.n,
    ).toBe(0);
  } finally {
    sqlite.close();
  }
});
it("R2 thành công nhưng D1 lỗi không công nhận; retry an toàn không nhân đôi feed/audit", async () => {
  const { db, sqlite } = fixture(),
    s = storage(),
    env = { DB: db, IMAGES: s.bucket } as unknown as Env;
  try {
    const digest = await hash(bytes);
    sqlite.exec(
      "CREATE TRIGGER fail_media_audit BEFORE INSERT ON audit_logs WHEN NEW.action='PRODUCT_IMAGE_UPLOAD' BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
    );
    await expect(media(env, actor, upload(), digest)).rejects.toThrow();
    expect(s.objects.size).toBe(1);
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM media_objects").get()?.n,
    ).toBe(0);
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM processed_mutations").get()?.n,
    ).toBe(0);
    sqlite.exec("DROP TRIGGER fail_media_audit");
    await media(env, actor, upload(), digest);
    expect(s.objects.size).toBe(1);
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM media_objects").get()?.n,
    ).toBe(1);
  } finally {
    sqlite.close();
  }
});
