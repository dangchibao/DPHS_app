import { describe, it, expect } from "vitest";
import {
  ApiError,
  checkPermission,
  money,
  constantEqual,
  passwordHash,
} from "../src/security";
import worker from "../src/index";
import type { Env } from "../src/index";

describe("RBAC API và kiểm tra đầu vào", () => {
  it("Thu ngân không điều chỉnh kho/xem lương, chủ được phép", () => {
    expect(() => checkPermission("cashier", "stock")).toThrow(ApiError);
    expect(() => checkPermission("cashier", "payroll")).toThrow(ApiError);
    expect(() => checkPermission("manager", "payroll")).toThrow(ApiError);
    expect(() => checkPermission("owner", "stock")).not.toThrow();
  });
  it("Tiền không nhận số lẻ, số âm hoặc vượt safe integer", () => {
    expect(money(125000)).toBe(125000);
    for (const value of [
      1.5,
      -1,
      NaN,
      Infinity,
      Number.MAX_SAFE_INTEGER + 1,
      "100",
    ])
      expect(() => money(value)).toThrow();
  });
  it("API chặn truy cập staff khi chưa đăng nhập", async () => {
    const response = await worker.fetch(
      new Request("http://localhost/staff"),
      {} as Env,
    );
    expect(response.status).toBe(401);
  });
  it("Password verifier có salt và so sánh đúng", async () => {
    const a = await passwordHash("test-password-only", "salt-1");
    const b = await passwordHash("test-password-only", "salt-2");
    expect(a).not.toBe(b);
    expect(constantEqual(a, a)).toBe(true);
    expect(constantEqual(a, b)).toBe(false);
  });
});
