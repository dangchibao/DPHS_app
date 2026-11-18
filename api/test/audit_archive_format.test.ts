import { it, expect } from "vitest";
import { gzipSync } from "node:zlib";
import {
  archiveSource,
  verifyArchiveGzip,
  auditRecordDigest,
} from "../src/audit_archive_format";
import { auditStatement } from "../src/audit";
import { fixture, actor } from "./report_fixtures";
const input = {
  id: "fixture-archive",
  store_id: "s1",
  device_id: "d1",
  direction: -1 as const,
  previous_index: 0,
  previous_hash: "",
  cutoff: "9999-01-01T00:00:00.000Z",
};
it("Nguồn archive xác minh chain API âm, gzip/readback và digest toàn bản ghi", async () => {
  const { db, sqlite } = fixture();
  try {
    await (await auditStatement(db, actor, "FIXTURE", "x", "Fixture")).run();
    await (await auditStatement(db, actor, "FIXTURE", "y", "Fixture")).run();
    const rows = sqlite
      .prepare("SELECT * FROM audit_logs ORDER BY chain_index DESC")
      .all();
    const source = await archiveSource(input, rows);
    expect(source.last_index).toBe(-2);
    expect(source.receipts.length).toBe(2);
    expect(
      await verifyArchiveGzip(
        gzipSync(source.bytes),
        source.source_hash,
        source.bytes.length,
      ),
    ).toBe(source.source);
    expect(
      await auditRecordDigest({ ...rows[0], server_time: "changed receipt" }),
    ).toBe(await auditRecordDigest(rows[0]));
    expect(
      await auditRecordDigest({ ...rows[0], app_version: "changed metadata" }),
    ).not.toBe(await auditRecordDigest(rows[0]));
    await expect(archiveSource(input, rows.reverse())).rejects.toThrow();
  } finally {
    sqlite.close();
  }
});
it("Chặn gzip lỗi/bomb/checksum sai và log mới hoặc bị sửa, không có thao tác xóa", async () => {
  const { db, sqlite } = fixture();
  try {
    await (await auditStatement(db, actor, "FIXTURE", "x", "Fixture")).run();
    const row = sqlite.prepare("SELECT * FROM audit_logs").get()!;
    await expect(
      archiveSource({ ...input, cutoff: "2000-01-01T00:00:00.000Z" }, [row]),
    ).rejects.toThrow();
    await expect(
      archiveSource(input, [{ ...row, reason: "tampered" }]),
    ).rejects.toThrow();
    await expect(
      verifyArchiveGzip(new Uint8Array([1, 2, 3]), "bad", 3),
    ).rejects.toThrow();
    await expect(
      verifyArchiveGzip(gzipSync("x".repeat(1000000)), "bad", 30),
    ).rejects.toThrow();
    const source = await archiveSource(input, [row]);
    await expect(
      verifyArchiveGzip(gzipSync(source.bytes), "bad", source.bytes.length),
    ).rejects.toThrow();
    expect(sqlite.prepare("SELECT COUNT(*) n FROM audit_logs").get()?.n).toBe(
      1,
    );
  } finally {
    sqlite.close();
  }
});
