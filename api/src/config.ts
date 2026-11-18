// Cấu hình tập trung; kiểm chứng 17/11/2026. Không dùng để tính hóa đơn.
export const cloudBudget = {
  workersRequestsPerDay: 100_000,
  workersCpuMs: 10,
  d1RowsReadPerDay: 5_000_000,
  d1RowsWrittenPerDay: 100_000,
  d1DatabaseBytes: 500_000_000,
  d1AccountBytes: 5_000_000_000,
  d1QueriesPerInvocation: 50,
  d1BoundParameters: 100,
  d1FunctionArguments: 32,
  resetHourUtc: 0,
  sources: [
    "https://developers.cloudflare.com/workers/platform/limits/",
    "https://developers.cloudflare.com/d1/platform/pricing/",
    "https://developers.cloudflare.com/d1/platform/limits/",
  ],
} as const;

// Nhận payload cũ 5 mutation nhưng chỉ xử lý/ack 3, phần còn lại ở outbox.
export const syncLimits = {
  maxRequestMutations: 5,
  maxProcessedMutations: 3,
} as const;
// Mức dữ liệu đồng bộ tối thiểu; không dùng header này thay kiểm tra quyền.
export const minimumSyncSchema = 30;
export const reportLimits = {
  pageRows: 25,
  pageBytes: 500000,
  cacheBytes: 250000,
  rebuildDocuments: 3,
  maxDays: 366,
  refreshEvents: 2000,
  refreshRows: 100,
} as const;
