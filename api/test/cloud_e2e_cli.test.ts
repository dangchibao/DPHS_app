import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, unlinkSync, rmdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { expect, it } from "vitest";

it("QA setup mặc định không chạy và không in bí mật", () => {
  const result = spawnSync(
    process.execPath,
    [resolve("scripts/prepare-cloud-e2e.mjs")],
    {
      encoding: "utf8",
      timeout: 10000,
      env: {
        ...process.env,
        PROVISION_OWNER_PASSWORD: "fixture-secret-never-log",
      },
    },
  );
  expect(result.status).toBe(1);
  expect(result.stdout).toBe("");
  expect(result.stderr.trim()).toBe("E2E_SETUP_OR_CLEANUP_FAILED");
  expect(result.stderr).not.toContain("fixture-secret-never-log");
});

it("QA setup từ chối config staging bàn giao trước khi gọi mạng", () => {
  const folder = mkdtempSync(join(tmpdir(), "nt-e2e-guard-"));
  const config = join(folder, "config.json");
  writeFileSync(
    config,
    JSON.stringify({
      name: "ngoc-thanh-pos-staging",
      d1_databases: [{ database_name: "ngoc-thanh-pos-staging" }],
      vars: {
        ALLOWED_ORIGIN:
          "https://ngoc-thanh-pos-staging.ngoc-thanh-161df6.workers.dev",
      },
    }),
  );
  try {
    const result = spawnSync(
      process.execPath,
      [
        resolve("scripts/prepare-cloud-e2e.mjs"),
        "--config",
        config,
        "--execute-cloud",
      ],
      { encoding: "utf8", timeout: 10000 },
    );
    expect(result.status).toBe(1);
    expect(result.stdout).toBe("");
    expect(result.stderr.trim()).toBe("E2E_SETUP_OR_CLEANUP_FAILED");
  } finally {
    unlinkSync(config);
    rmdirSync(folder);
  }
});
