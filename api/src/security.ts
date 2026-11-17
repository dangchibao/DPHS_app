export type Role = "owner" | "manager" | "cashier" | "warehouse" | "accountant";
export type Permission =
  | "attendance"
  | "reserve"
  | "returns"
  | "voidInvoice"
  | "tailoring"
  | "collect"
  | "sell"
  | "catalog"
  | "stock"
  | "staff"
  | "payroll"
  | "audit"
  | "backup"
  | "reports"
  | "configure";
export const rolePermissions: Record<Role, readonly Permission[]> = {
  owner: [
    "attendance",
    "reserve",
    "returns",
    "voidInvoice",
    "tailoring",
    "collect",
    "sell",
    "catalog",
    "stock",
    "staff",
    "payroll",
    "audit",
    "backup",
    "reports",
    "configure",
  ],
  manager: [
    "attendance",
    "reserve",
    "returns",
    "voidInvoice",
    "tailoring",
    "sell",
    "collect",
    "catalog",
    "stock",
    "staff",
    "audit",
    "backup",
    "reports",
  ],
  cashier: ["sell", "collect", "tailoring", "returns", "reserve"],
  warehouse: ["stock", "tailoring", "reserve"],
  accountant: ["payroll", "reports", "collect", "attendance"],
};
export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public code = "VALIDATION",
  ) {
    super(message);
  }
}
export function checkPermission(
  role: Role,
  permission: Permission,
  issuedRole?: Role,
): void {
  if (
    !rolePermissions[role]?.includes(permission) ||
    (issuedRole !== undefined &&
      !rolePermissions[issuedRole]?.includes(permission))
  )
    throw new ApiError(
      403,
      "Không có quyền thực hiện thao tác này.",
      "FORBIDDEN",
    );
}
const encoder = new TextEncoder();
export function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
export async function sha256(value: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}
export function randomToken(): string {
  return hex(crypto.getRandomValues(new Uint8Array(32)).buffer);
}
export async function passwordHash(
  credential: string,
  salt: string,
): Promise<string> {
  // PBKDF2-SHA256/600000 nằm ở client. DB chỉ giữ hash lớp ngoài,
  // không giữ credential có thể dùng lại để đăng nhập.
  return `client-v1:${await sha256(`ngoc-thanh:credential:v1:${salt}:${credential}`)}`;
}
export function credential(value: unknown): string {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value))
    throw new ApiError(400, "Thông tin xác thực không hợp lệ.");
  return value;
}
export function constantEqual(a: string, b: string): boolean {
  let diff = a.length ^ b.length;
  for (let i = 0; i < a.length; i++)
    diff |= a.charCodeAt(i) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}
export function text(value: unknown, field: string, max = 200): string {
  if (typeof value !== "string" || !value.trim() || value.length > max)
    throw new ApiError(400, `${field} không hợp lệ.`);
  return value.trim();
}
export function money(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0)
    throw new ApiError(400, "Tiền phải là số nguyên VND không âm.");
  return value;
}
