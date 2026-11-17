import { ApiError } from "./security";

export function utcInstant(value: unknown, label: string): number {
  if (
    typeof value !== "string" ||
    !Number.isFinite(Date.parse(value)) ||
    new Date(value).toISOString() !== value
  )
    throw new ApiError(400, `${label} phải là thời điểm UTC hợp lệ.`);
  return Date.parse(value);
}
export function reservationState(
  created: string,
  expires: string,
  at: string,
  resolution: { kind: "release" | "consume"; created_at: string } | null = null,
): "active" | "expired" | "released" | "consumed" | "future" {
  const start = utcInstant(created, "Ngày giữ"),
    end = utcInstant(expires, "Hạn giữ"),
    time = utcInstant(at, "Thời điểm kiểm tra");
  if (end <= start) throw new ApiError(400, "Hạn giữ phải sau ngày nhận giữ.");
  if (time < start) return "future";
  if (
    resolution &&
    utcInstant(resolution.created_at, "Ngày giải phóng") <= time
  )
    return resolution.kind === "release" ? "released" : "consumed";
  return time < end ? "active" : "expired";
}
