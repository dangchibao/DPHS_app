import { it, expect } from "vitest";
import { reservationState, utcInstant } from "../src/reservation_time";
const start = "2026-11-15T01:00:00.000Z",
  end = "2026-11-15T03:00:00.000Z";
it("Giữ hàng có hiệu lực ở đầu khoảng và hết hạn đúng thời điểm", () => {
  expect(reservationState(start, end, start)).toBe("active");
  expect(reservationState(start, end, end)).toBe("expired");
  expect(reservationState(start, end, "2026-11-15T00:59:59.999Z")).toBe(
    "future",
  );
});
it("Sự kiện tương lai không giải phóng ngược lần giữ ở quá khứ", () => {
  const event = {
    kind: "release" as const,
    created_at: "2026-11-15T02:00:00.000Z",
  };
  expect(reservationState(start, end, "2026-11-15T01:30:00.000Z", event)).toBe(
    "active",
  );
  expect(reservationState(start, end, event.created_at, event)).toBe(
    "released",
  );
  expect(
    reservationState(start, end, event.created_at, {
      ...event,
      kind: "consume",
    }),
  ).toBe("consumed");
});
it("Từ chối ngày không chuẩn, thiếu múi giờ hoặc hạn không sau ngày giữ", () => {
  expect(() => utcInstant("2026-11-15", "Ngày")).toThrow();
  expect(() => reservationState(start, start, start)).toThrow();
});
