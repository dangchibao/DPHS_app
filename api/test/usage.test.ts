import { it, expect } from "vitest";
import { usage, usageMeter } from "../src/usage";
import type { Env } from "../src/index";
import { actor } from "./report_fixtures";
const db = () =>
  ({
    prepare: () => ({ run: async () => ({ meta: { size_after: 400000000 } }) }),
  }) as unknown as D1Database;
it("Ngưỡng 80/100%, số chưa đo không biến thành 0", () => {
  expect(usageMeter("x", "x", 79, 100).level).toBe("normal");
  expect(usageMeter("x", "x", 80, 100).level).toBe("warning");
  expect(usageMeter("x", "x", 100, 100).level).toBe("limit");
  for (const v of [undefined, null, -1, NaN, 9007199254740992])
    expect(usageMeter("x", "x", v, 100)).toMatchObject({
      used: null,
      percent: null,
      level: "unknown",
    });
});
it("Thiếu token không gọi mạng; cache vẫn kiểm quyền hiện tại và lúc cấp", async () => {
  let calls = 0;
  const transport = (async () => {
      calls++;
      throw Error("should not fetch");
    }) as typeof fetch,
    env = { DB: db() } as Env;
  const result = (await (
    await usage(env, actor, new Date("2026-11-17T03:00:00Z"), transport)
  ).json()) as {
    state: string;
    meters: { key: string; used: number | null }[];
  };
  expect(result.state).toBe("not_configured");
  expect(calls).toBe(0);
  expect(result.meters.find((m) => m.key === "requests")?.used).toBeNull();
  expect(result.meters.find((m) => m.key === "storage")?.used).toBe(400000000);
  for (const role of ["manager", "accountant", "cashier", "warehouse"] as const)
    await expect(usage(env, { ...actor, role })).rejects.toThrow();
  await expect(
    usage(env, { ...actor, issued_role: "cashier" }),
  ).rejects.toThrow();
});
it("Analytics đúng account/UTC, cache 60s không mang ngày cũ qua reset, không trả secret", async () => {
  let calls = 0;
  const env = {
    DB: db(),
    CF_ANALYTICS_TOKEN: "fixture-only-secret",
    CLOUDFLARE_ACCOUNT_ID: "a".repeat(32),
  } as Env;
  const transport = (async (url, init) => {
    calls++;
    expect(url).toBe("https://api.cloudflare.com/client/v4/graphql");
    expect((init!.headers as Record<string, string>).Authorization).toBe(
      "Bearer fixture-only-secret",
    );
    const body = JSON.parse(init!.body as string);
    expect(body.variables.account).toBe("a".repeat(32));
    expect(body.query).not.toContain("fixture-only-secret");
    return Response.json({
      data: {
        viewer: {
          accounts: [
            {
              d1AnalyticsAdaptiveGroups: [
                { sum: { rowsRead: 1000, rowsWritten: 85000 } },
              ],
              workersInvocationsAdaptive: [{ sum: { requests: 80000 } }],
            },
          ],
        },
      },
    });
  }) as typeof fetch;
  const first = (await (
    await usage(env, actor, new Date("2026-11-17T23:59:50Z"), transport)
  ).json()) as { reset_at: string; meters: { key: string; level: string }[] };
  expect(first.reset_at).toBe("2026-11-18T00:00:00.000Z");
  expect(first.meters.find((m) => m.key === "write")?.level).toBe("warning");
  expect(JSON.stringify(first)).not.toContain(env.CF_ANALYTICS_TOKEN);
  await usage(env, actor, new Date("2026-11-17T23:59:55Z"), transport);
  expect(calls).toBe(1);
  await usage(env, actor, new Date("2026-11-18T00:00:05Z"), transport);
  expect(calls).toBe(2);
});
it("Analytics lỗi không bịa 0; budget phải là số nguyên dương", async () => {
  const env = {
    DB: db(),
    CF_ANALYTICS_TOKEN: "fixture",
    CLOUDFLARE_ACCOUNT_ID: "a".repeat(32),
    CLOUD_BUDGET_JSON: '{"d1RowsWrittenPerDay":200000}',
  } as Env;
  const result = (await (
    await usage(env, actor, new Date("2026-11-17"), (async () =>
      Response.json({
        errors: [{ message: "sensitive upstream error" }],
      })) as typeof fetch)
  ).json()) as {
    state: string;
    meters: { key: string; used: number | null; limit: number }[];
  };
  expect(result.state).toBe("unavailable");
  expect(result.meters.find((m) => m.key === "write")).toMatchObject({
    used: null,
    limit: 200000,
  });
  expect(JSON.stringify(result)).not.toContain("sensitive");
  for (const value of [
    "null",
    "[]",
    '{"unknown":1}',
    '{"workersCpuMs":0}',
    '{"workersCpuMs":1.5}',
  ])
    await expect(
      usage({ ...env, CLOUD_BUDGET_JSON: value }, actor),
    ).rejects.toThrow();
});
