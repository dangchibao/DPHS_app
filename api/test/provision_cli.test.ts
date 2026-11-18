import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, unlinkSync, rmdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

describe("CLI provision: mặc định không ghi cloud và không in secrets", () => {
  const password = "fixture-owner-password-only";
  function run(extra: string[]) {
    const folder = mkdtempSync(join(tmpdir(), "nt-provision-cli-"));
    const file = join(folder, "config.json");
    writeFileSync(
      file,
      JSON.stringify({
        account_id: "a".repeat(32),
        vars: { ENVIRONMENT: "production" },
        d1_databases: [
          {
            binding: "DB",
            database_name: "fixture",
            database_id: "11111111-1111-4111-8111-111111111111",
          },
        ],
      }),
    );
    try {
      return spawnSync(
        process.execPath,
        [resolve("scripts/provision-owner.mjs"), "--config", file, ...extra],
        {
          encoding: "utf8",
          timeout: 15000,
          env: {
            ...process.env,
            PROVISION_OWNER_PASSWORD: password,
            CLOUDFLARE_API_TOKEN: "fixture-token-never-log",
          },
        },
      );
    } finally {
      unlinkSync(file);
      rmdirSync(folder);
    }
  }
  it("Preview không cần Cloudflare, chỉ trả metadata công khai", () => {
    const result = run([]);
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      mode: "preview",
      changes: false,
      username: "admin",
    });
    expect(result.stdout + result.stderr).not.toContain(password);
    expect(result.stdout + result.stderr).not.toContain(
      "fixture-token-never-log",
    );
  });
  it("Cờ ghi thiếu UUID xác nhận dừng trước mọi truy cập cloud", () => {
    const result = run([
      "--execute-cloud",
      "--confirm-empty-database",
      "wrong-target",
    ]);
    expect(result.status).toBe(1);
    expect(JSON.parse(result.stderr).error).toBe("PROVISION_CONFIRM_REQUIRED");
    expect(result.stdout + result.stderr).not.toContain(password);
    expect(result.stdout + result.stderr).not.toContain(
      "fixture-token-never-log",
    );
  });
});
