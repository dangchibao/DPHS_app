import type { Actor } from "./auth";
import type { Env } from "./index";
import { ApiError, checkPermission } from "./security";
import { cloudBudget } from "./config";
type Meter = {
  key: string;
  label: string;
  used: number | null;
  limit: number;
  percent: number | null;
  level: "unknown" | "normal" | "warning" | "limit";
};
export function usageMeter(
  key: string,
  label: string,
  value: unknown,
  limit: number,
): Meter {
  const used =
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0
      ? value
      : null;
  const percent =
    used === null ? null : Number((BigInt(used) * 100n) / BigInt(limit));
  return {
    key,
    label,
    used,
    limit,
    percent,
    level:
      percent === null
        ? "unknown"
        : percent >= 100
          ? "limit"
          : percent >= 80
            ? "warning"
            : "normal",
  };
}
const fields = [
  "workersRequestsPerDay",
  "workersCpuMs",
  "d1RowsReadPerDay",
  "d1RowsWrittenPerDay",
  "d1DatabaseBytes",
  "d1AccountBytes",
] as const;
function limits(env: Env) {
  const result: Record<string, number> = Object.fromEntries(
    fields.map((k) => [k, cloudBudget[k]]),
  );
  if (env.CLOUD_BUDGET_JSON) {
    let override: Record<string, unknown>;
    try {
      override = JSON.parse(env.CLOUD_BUDGET_JSON);
    } catch {
      throw new ApiError(
        503,
        "Cấu hình ngân sách cloud không hợp lệ.",
        "BUDGET_CONFIGURATION",
      );
    }
    if (
      !override ||
      typeof override !== "object" ||
      Array.isArray(override) ||
      Object.keys(override).some(
        (k) => !fields.includes(k as (typeof fields)[number]),
      )
    )
      throw new ApiError(
        503,
        "Cấu hình ngân sách cloud không hợp lệ.",
        "BUDGET_CONFIGURATION",
      );
    for (const [k, v] of Object.entries(override)) {
      if (typeof v !== "number" || !Number.isSafeInteger(v) || v < 1)
        throw new ApiError(
          503,
          "Cấu hình ngân sách cloud không hợp lệ.",
          "BUDGET_CONFIGURATION",
        );
      result[k] = v;
    }
  }
  return result;
}
const query = `query NgocThanhUsage($account: string!, $date: Date!, $start: Time!, $end: Time!) {
 viewer { accounts(filter:{accountTag:$account}) {
  d1AnalyticsAdaptiveGroups(limit:1,filter:{date_geq:$date,date_leq:$date}) { sum { rowsRead rowsWritten } }
  workersInvocationsAdaptive(limit:1,filter:{datetime_geq:$start,datetime_lt:$end}) { sum { requests } }
 } }
}`;
type Snapshot = Record<string, unknown>;
const cache = new WeakMap<
  D1Database,
  { key: string; expires: number; data: Promise<Snapshot> }
>();
export async function usage(
  env: Env,
  actor: Actor,
  now = new Date(),
  transport: typeof fetch = fetch,
): Promise<Response> {
  checkPermission(actor.role, "configure", actor.issued_role);
  const day = now.toISOString().slice(0, 10),
    budget = limits(env),
    key = [
      day,
      env.CLOUDFLARE_ACCOUNT_ID,
      env.CF_ANALYTICS_TOKEN,
      env.CLOUD_BUDGET_JSON,
    ].join("|");
  let stored = cache.get(env.DB);
  if (!stored || stored.key !== key || stored.expires <= now.getTime()) {
    const work = (async () => {
      const end = new Date(day + "T00:00:00.000Z");
      end.setUTCDate(end.getUTCDate() + 1);
      let rowsRead: unknown = null,
        rowsWritten: unknown = null,
        requests: unknown = null,
        size: unknown = null;
      let state = "not_configured";
      try {
        const meta = await env.DB.prepare("SELECT 1").run();
        size = meta.meta.size_after;
      } catch {
        /* Metrics must not scan business tables or claim 0. */
      }
      if (env.CF_ANALYTICS_TOKEN && env.CLOUDFLARE_ACCOUNT_ID) {
        state = "unavailable";
        try {
          const response = await transport(
            "https://api.cloudflare.com/client/v4/graphql",
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${env.CF_ANALYTICS_TOKEN}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                query,
                variables: {
                  account: env.CLOUDFLARE_ACCOUNT_ID,
                  date: day,
                  start: day + "T00:00:00.000Z",
                  end: end.toISOString(),
                },
              }),
              signal: AbortSignal.timeout(8000),
            },
          );
          if (response.ok) {
            const body = (await response.json()) as {
              errors?: unknown[];
              data?: {
                viewer?: {
                  accounts?: {
                    d1AnalyticsAdaptiveGroups?: {
                      sum?: { rowsRead?: unknown; rowsWritten?: unknown };
                    }[];
                    workersInvocationsAdaptive?: {
                      sum?: { requests?: unknown };
                    }[];
                  }[];
                };
              };
            };
            const account = body.data?.viewer?.accounts?.[0];
            if (!body.errors?.length && account) {
              // Empty arrays indicate no matching execution data, not proof of zero
              // billing (collection can lag or omit pre-execution platform failures).
              rowsRead = account.d1AnalyticsAdaptiveGroups?.[0]?.sum?.rowsRead;
              rowsWritten =
                account.d1AnalyticsAdaptiveGroups?.[0]?.sum?.rowsWritten;
              requests = account.workersInvocationsAdaptive?.[0]?.sum?.requests;
              state = "analytics";
            }
          }
        } catch {
          /* Return explicit unavailable; never expose upstream errors/secrets. */
        }
      }
      return {
        state,
        day_utc: day,
        generated_at: now.toISOString(),
        reset_at: end.toISOString(),
        refresh_after_seconds: 60,
        cpu_limit_ms: budget.workersCpuMs,
        account_storage_limit_bytes: budget.d1AccountBytes,
        meters: [
          usageMeter(
            "requests",
            "Requests Workers toàn account / ngày",
            requests,
            budget.workersRequestsPerDay,
          ),
          usageMeter(
            "read",
            "Rows read D1 toàn account / ngày",
            rowsRead,
            budget.d1RowsReadPerDay,
          ),
          usageMeter(
            "write",
            "Rows written D1 toàn account / ngày",
            rowsWritten,
            budget.d1RowsWrittenPerDay,
          ),
          usageMeter(
            "storage",
            "Dung lượng database POS (byte)",
            size,
            budget.d1DatabaseBytes,
          ),
        ],
        note: "Analytics có độ trễ/lấy mẫu; số không có chưa được coi là 0. Dung lượng account D1/R2 và CPU từng request cần kiểm tra thêm trên Cloudflare. Hạn mức ngày reset 07:00 Việt Nam. Không tự đổi gói.",
        sources: cloudBudget.sources,
      };
    })();
    stored = { key, expires: now.getTime() + 60000, data: work };
    cache.set(env.DB, stored);
  }
  return Response.json(await stored.data);
}
