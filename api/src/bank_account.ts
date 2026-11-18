import { ApiError, text } from "./security";
export function bankConfig(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new ApiError(400, "Cấu hình chuyển khoản không hợp lệ.");
  const row = value as Record<string, unknown>;
  if (
    Object.keys(row).sort().join(",") !==
    "account_holder,account_number,bank_name,qr_png"
  )
    throw new ApiError(400, "Trường cấu hình chuyển khoản không hợp lệ.");
  text(row.bank_name, "Ngân hàng", 100);
  text(row.account_holder, "Chủ tài khoản", 100);
  if (
    typeof row.account_number !== "string" ||
    !/^[A-Za-z0-9 .-]{3,40}$/.test(row.account_number)
  )
    throw new ApiError(400, "Số tài khoản không hợp lệ.");
  if (
    typeof row.qr_png !== "string" ||
    row.qr_png.length > 87384 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
      row.qr_png,
    )
  )
    throw new ApiError(400, "Ảnh QR không hợp lệ.");
  if (row.qr_png) {
    const data = atob(row.qr_png),
      sig = [137, 80, 78, 71, 13, 10, 26, 10];
    const n = (i: number) =>
      data.charCodeAt(i) * 16777216 +
      (data.charCodeAt(i + 1) << 16) +
      (data.charCodeAt(i + 2) << 8) +
      data.charCodeAt(i + 3);
    if (
      data.length > 65536 ||
      data.length < 33 ||
      sig.some((v, i) => data.charCodeAt(i) !== v) ||
      data.slice(12, 16) !== "IHDR" ||
      n(16) < 1 ||
      n(20) < 1 ||
      n(16) > 1024 ||
      n(20) > 1024
    )
      throw new ApiError(400, "Ảnh QR phải là PNG tối đa 64KB, 1024×1024.");
  }
  return row;
}
