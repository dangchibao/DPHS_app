import { it, expect } from "vitest";
import { bankConfig } from "../src/bank_account";
import { push } from "../src/sync";
import { fixture, actor } from "./report_fixtures";
const config = {
  bank_name: "Ngân hàng mẫu",
  account_number: "0123456789",
  account_holder: "NGOC THANH",
  qr_png: "",
};
const row = (key = "2026-11-17T00:00:00.000Z|d1|1") => ({
  id: "s1",
  store_id: "s1",
  device_id: "d1",
  user_id: "u1",
  config_json: JSON.stringify(config),
  updated_at: key.split("|")[0],
  lww_key: key,
});
const body = (id: string, value = row()) => ({
  mutations: [{ id, records: [{ table: "bank_accounts", row: value }] }],
});
it("Cấu hình ngân hàng chỉ chủ có quyền hiện tại và quyền lúc cấp; scope và replay được kiểm tra", async () => {
  const { db, sqlite } = fixture();
  try {
    for (const role of [
      "cashier",
      "manager",
      "warehouse",
      "accountant",
    ] as const)
      await expect(push(db, { ...actor, role }, body(role))).rejects.toThrow();
    await expect(
      push(db, { ...actor, issued_role: "cashier" }, body("issued")),
    ).rejects.toThrow();
    await expect(
      push(db, actor, body("scope", { ...row(), store_id: "other" })),
    ).rejects.toThrow();
    await push(db, actor, body("bank-1"));
    await push(db, actor, body("bank-1"));
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM bank_accounts").get()?.n,
    ).toBe(1);
    expect(
      sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM audit_logs WHERE action='BANK_ACCOUNT_SYNC'",
        )
        .get()?.n,
    ).toBe(1);
    await expect(
      push(
        db,
        actor,
        body("bank-1", {
          ...row(),
          config_json: JSON.stringify({ ...config, account_number: "999999" }),
        }),
      ),
    ).rejects.toThrow(/ID/);
    await push(db, actor, body("old", row("2026-11-16T00:00:00.000Z|d1|old")));
    expect(
      sqlite.prepare("SELECT lww_key FROM bank_accounts").get()?.lww_key,
    ).toBe(row().lww_key);
  } finally {
    sqlite.close();
  }
});
it("PNG nhỏ được nhận; SVG, base64 sai, kích thước lớn hoặc khóa JSON lạ bị chặn", () => {
  const png =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=";
  expect(bankConfig({ ...config, qr_png: png })).toMatchObject(
    config.bank_name ? { bank_name: config.bank_name } : {},
  );
  for (const value of [
    { ...config, qr_png: "<svg></svg>" },
    { ...config, qr_png: "A".repeat(90000) },
    { ...config, extra: true },
    { ...config, account_number: "x" },
    { ...config, bank_name: "" },
  ])
    expect(() => bankConfig(value)).toThrow();
  const data = Uint8Array.from(atob(png), (c) => c.charCodeAt(0));
  new DataView(data.buffer).setUint32(16, 5000);
  expect(() =>
    bankConfig({ ...config, qr_png: btoa(String.fromCharCode(...data)) }),
  ).toThrow();
});
it("Lỗi audit rollback cả cấu hình và ACK trong cùng transaction", async () => {
  const { db, sqlite } = fixture();
  try {
    sqlite.exec(
      "CREATE TRIGGER fail_bank_audit BEFORE INSERT ON audit_logs WHEN NEW.action='BANK_ACCOUNT_SYNC' BEGIN SELECT RAISE(ABORT,'fixture audit error'); END",
    );
    await expect(push(db, actor, body("rollback"))).rejects.toThrow();
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM bank_accounts").get()?.n,
    ).toBe(0);
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM processed_mutations").get()?.n,
    ).toBe(0);
  } finally {
    sqlite.close();
  }
});
