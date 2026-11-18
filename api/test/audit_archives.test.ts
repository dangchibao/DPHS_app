import { it, expect } from "vitest";
import { gzipSync } from "node:zlib";
import { fixture, actor } from "./report_fixtures";
import { auditArchives, archiveObject } from "../src/audit_archives";
import { sha256 } from "../src/security";
import { push } from "../src/sync";
import { auditStatement, clientAuditHead } from "../src/audit";
import type { Env } from "../src/index";
const id = (n: number) =>
  `019c4b00-0000-7000-8000-${String(n).padStart(12, "0")}`;
const url = new URL("https://fixture.test/audit/archives");
async function row(n: number, previous = "") {
  const changes = {},
    base = {
      id: `old-${n}`,
      store_id: "s1",
      device_id: "d1",
      user_id: "u1",
      role: "owner",
      action: "PRODUCT_UPDATE",
      entity_type: "variant",
      entity_id: "v1",
      changes,
      reason: "Fixture",
      client_time: "2019-01-01T00:00:00.000Z",
      severity: "normal",
      hash_prev: previous,
      chain_index: n,
    };
  return {
    id: base.id,
    store_id: base.store_id,
    device_id: base.device_id,
    user_id: base.user_id,
    role: base.role,
    action: base.action,
    entity_type: base.entity_type,
    entity_id: base.entity_id,
    document_code: null,
    changes_json: JSON.stringify(changes),
    reason: base.reason,
    client_time: base.client_time,
    server_time: base.client_time,
    app_version: "fixture",
    severity: base.severity,
    hash_prev: previous,
    hash: await sha256(JSON.stringify(base)),
    chain_index: n,
  };
}
async function setup() {
  const f = fixture(),
    one = await row(1),
    two = await row(2, one.hash);
  for (const r of [one, two]) {
    f.sqlite
      .prepare(
        `INSERT INTO audit_logs VALUES(${Object.keys(r)
          .map(() => "?")
          .join(",")})`,
      )
      .run(...Object.values(r));
    f.sqlite
      .prepare(
        "INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) VALUES(?,?,?,?,?,?)",
      )
      .run("s1", r.id, "audit_logs", r.id, JSON.stringify(r), r.client_time);
  }
  const objects = new Map<string, Uint8Array>();
  let failRead = false;
  const bucket = {
    put: async (key: string, value: Uint8Array) => {
      objects.set(key, new Uint8Array(value));
    },
    get: async (key: string) => {
      const bytes = objects.get(key);
      return failRead || !bytes
        ? null
        : { size: bytes.length, body: new Response(bytes).body };
    },
  } as unknown as R2Bucket;
  const env = { DB: f.db, AUDIT_ARCHIVES: bucket } as Env;
  const prepare = async () =>
    (await (
      await auditArchives(env, actor, url, {
        action: "prepare",
        id: id(1),
        store_id: "s1",
        device_id: "d1",
        direction: 1,
      })
    ).json()) as { manifest: Record<string, unknown>; source_base64: string };
  const upload = async (bytes: Uint8Array) =>
    archiveObject(
      env,
      actor,
      id(1),
      new Request(`https://fixture.test/audit/archives/${id(1)}`, {
        method: "PUT",
        body: bytes,
      }),
    );
  const commit = () =>
    auditArchives(env, actor, url, {
      action: "commit",
      id: id(1),
      confirmed: true,
    });
  return {
    ...f,
    one,
    two,
    objects,
    env,
    prepare,
    upload,
    commit,
    setFailRead: (value: boolean) => {
      failRead = value;
    },
  };
}
it("Archive verified/readback trước giảm log; giữ checkpoint, replay cũ và nhận log mới nối chain", async () => {
  const f = await setup();
  try {
    const plan = await f.prepare(),
      compressed = gzipSync(Buffer.from(plan.source_base64, "base64"));
    await expect(f.commit()).rejects.toThrow();
    await f.upload(compressed);
    expect(() =>
      f.sqlite.exec("DELETE FROM audit_logs WHERE chain_index>0"),
    ).toThrow(/append-only/);
    await f.commit();
    await f.commit();
    expect(
      f.sqlite
        .prepare("SELECT COUNT(*) n FROM audit_logs WHERE chain_index>0")
        .get()?.n,
    ).toBe(0);
    expect(
      f.sqlite.prepare("SELECT COUNT(*) n FROM audit_archive_receipts").get()
        ?.n,
    ).toBe(2);
    expect(
      f.sqlite
        .prepare(
          "SELECT COUNT(*) n FROM change_feed WHERE entity_type='audit_logs' AND entity_id LIKE 'old-%'",
        )
        .get()?.n,
    ).toBe(0);
    expect((await clientAuditHead(f.db, "s1", "d1"))?.chain_index).toBe(2);
    const envelope = (n: number, r: Record<string, unknown>) => ({
      mutations: [
        {
          id: id(n),
          records: [{ table: "audit_logs", row: { ...r, server_time: null } }],
        },
      ],
    });
    await push(f.db, actor, envelope(50, f.one));
    expect(
      f.sqlite
        .prepare("SELECT COUNT(*) n FROM audit_logs WHERE chain_index>0")
        .get()?.n,
    ).toBe(0);
    await expect(
      push(
        f.db,
        actor,
        envelope(51, { ...f.one, app_version: "tampered metadata" }),
      ),
    ).rejects.toThrow();
    const third = await row(3, f.two.hash);
    await push(f.db, actor, envelope(52, third));
    expect(
      f.sqlite
        .prepare("SELECT chain_index FROM audit_logs WHERE chain_index>0")
        .get()?.chain_index,
    ).toBe(3);
    const downloaded = await archiveObject(
      f.env,
      actor,
      id(1),
      new Request(`https://fixture.test/audit/archives/${id(1)}`),
    );
    expect(new Uint8Array(await downloaded.arrayBuffer())).toEqual(
      new Uint8Array(compressed),
    );
  } finally {
    f.sqlite.close();
  }
});
it("R2 hỏng/readback mất hoặc rollback transaction không làm mất log", async () => {
  const f = await setup();
  try {
    const plan = await f.prepare(),
      compressed = gzipSync(Buffer.from(plan.source_base64, "base64"));
    await expect(f.upload(gzipSync("wrong source"))).rejects.toThrow();
    f.setFailRead(true);
    await expect(f.upload(compressed)).rejects.toThrow();
    expect(
      f.sqlite.prepare("SELECT status FROM audit_archives").get()?.status,
    ).toBe("prepared");
    f.setFailRead(false);
    await f.upload(compressed);
    f.setFailRead(true);
    await expect(f.commit()).rejects.toThrow();
    f.setFailRead(false);
    f.sqlite.exec(
      "CREATE TRIGGER fail_archive_feed BEFORE DELETE ON change_feed WHEN OLD.entity_id LIKE 'old-%' BEGIN SELECT RAISE(ABORT,'fixture fail'); END;",
    );
    await expect(f.commit()).rejects.toThrow();
    expect(
      f.sqlite
        .prepare("SELECT COUNT(*) n FROM audit_logs WHERE chain_index>0")
        .get()?.n,
    ).toBe(2);
    expect(
      f.sqlite.prepare("SELECT COUNT(*) n FROM audit_archive_receipts").get()
        ?.n,
    ).toBe(0);
    expect(
      f.sqlite.prepare("SELECT COUNT(*) n FROM audit_chain_checkpoints").get()
        ?.n,
    ).toBe(0);
    expect(
      f.sqlite.prepare("SELECT status FROM audit_archives").get()?.status,
    ).toBe("verified");
    f.sqlite.exec("DROP TRIGGER fail_archive_feed");
    await f.commit();
  } finally {
    f.sqlite.close();
  }
});
it("Chỉ owner current+issued được giảm log; thiếu bucket, sai scope và log mới đều giữ nguyên", async () => {
  const f = await setup();
  try {
    for (const a of [
      { ...actor, role: "manager" as const },
      { ...actor, issued_role: "cashier" as const },
    ])
      await expect(
        auditArchives(f.env, a, url, {
          action: "prepare",
          id: id(1),
          device_id: "d1",
          direction: 1,
        }),
      ).rejects.toThrow();
    await expect(
      auditArchives({ DB: f.db } as Env, actor, url, {
        action: "prepare",
        id: id(1),
        device_id: "d1",
        direction: 1,
      }),
    ).rejects.toThrow();
    await expect(
      auditArchives(f.env, actor, url, {
        action: "prepare",
        id: id(1),
        store_id: "other",
        device_id: "d1",
        direction: 1,
      }),
    ).rejects.toThrow();
    await f.prepare();
    await expect(
      auditArchives(
        f.env,
        { ...actor, store_id: "other", role: "manager" },
        new URL("https://fixture.test/audit/archives?store=s1"),
      ),
    ).rejects.toThrow();
    await auditArchives({ DB: f.db } as Env, actor, url, {
      action: "cancel",
      id: id(1),
      reason: "Fixture cancel",
    });
    await expect(f.commit()).rejects.toThrow();
    expect(
      f.sqlite
        .prepare("SELECT COUNT(*) n FROM audit_logs WHERE chain_index>0")
        .get()?.n,
    ).toBe(2);
    await (await auditStatement(f.db, actor, "FIXTURE", "x", "Recent")).run();
    await expect(
      auditArchives(f.env, actor, url, {
        action: "prepare",
        id: id(2),
        device_id: "d1",
        direction: -1,
      }),
    ).rejects.toThrow();
  } finally {
    f.sqlite.close();
  }
});

it("Archive chain API âm tiếp tục giảm số và commit cạnh tranh không nhân bản checkpoint", async () => {
  const f = await setup();
  try {
    const one = await row(-1),
      two = await row(-2, one.hash);
    for (const r of [one, two])
      f.sqlite
        .prepare(
          `INSERT INTO audit_logs(${Object.keys(r).join(",")}) VALUES(${Object.keys(
            r,
          )
            .map(() => "?")
            .join(",")})`,
        )
        .run(...Object.values(r));
    const archiveId = id(7),
      prepared = (await (
        await auditArchives(f.env, actor, url, {
          action: "prepare",
          id: archiveId,
          store_id: "s1",
          device_id: "d1",
          direction: -1,
        })
      ).json()) as { source_base64: string };
    const compressed = gzipSync(Buffer.from(prepared.source_base64, "base64"));
    await archiveObject(
      f.env,
      actor,
      archiveId,
      new Request("https://fixture.test/audit/archives/" + archiveId, {
        method: "PUT",
        body: compressed,
      }),
    );
    const commit = () =>
      auditArchives(f.env, actor, url, {
        action: "commit",
        id: archiveId,
        confirmed: true,
      });
    const results = await Promise.allSettled([commit(), commit()]);
    expect(results.some((r) => r.status === "fulfilled")).toBe(true);
    await commit();
    expect(
      f.sqlite.prepare("SELECT COUNT(*) n FROM audit_chain_checkpoints").get()
        ?.n,
    ).toBe(1);
    expect(
      f.sqlite.prepare("SELECT COUNT(*) n FROM audit_archive_receipts").get()
        ?.n,
    ).toBe(2);
    expect(
      f.sqlite.prepare("SELECT MIN(chain_index) n FROM audit_logs").get()?.n,
    ).toBe(-5);
    await (
      await auditStatement(f.db, actor, "FIXTURE", "x", "Continue API chain")
    ).run();
    expect(
      f.sqlite.prepare("SELECT MIN(chain_index) n FROM audit_logs").get()?.n,
    ).toBe(-6);
    expect(() => f.sqlite.exec("DELETE FROM audit_archive_receipts")).toThrow();
  } finally {
    f.sqlite.close();
  }
});
