import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { management, enrollDevice } from "../src/management";
import type { Actor } from "../src/auth";

const actor: Actor = {
  user_id: "u1",
  store_id: "s1",
  device_id: "d1",
  role: "owner",
  name: "Chủ",
  session_id: "session",
};
const id = "019c4b00-0000-7000-8000-000000000001",
  assignment = "019c4b00-0000-7000-8000-000000000002",
  device = "019c4b00-0000-7000-8000-000000000003",
  enrollment = "019c4b00-0000-7000-8000-000000000004";
function fixture() {
  const d = testDatabase();
  d.sqlite.exec(`INSERT INTO stores VALUES('s1','NT-CN01','CN01',1,'2026');
    INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy chủ','approved','2026');
    INSERT INTO users VALUES('u1','admin','Chủ','hash','salt',1,0,'2026'),('u2','staff','Nhân viên','hash','salt',1,0,'2026');
    INSERT INTO employee_store_assignments VALUES('owner','s1','u1','owner',1,'2026');`);
  return d;
}
const storeBody = {
  action: "create_store",
  id,
  assignment_id: assignment,
  code: "NT-CN02",
  name: "Chi nhánh 02",
  reason: "Mở chi nhánh",
};
const inviteBody = {
  action: "invite_device",
  id: device,
  enrollment_id: enrollment,
  store_id: id,
  code: "B3",
  name: "Máy B3",
  reason: "Máy mới",
};
it("Chủ tạo cửa hàng, mời máy, gắn bản cài, duyệt và thu hồi vĩnh viễn", async () => {
  const d = fixture();
  try {
    await management(d.db, actor, storeBody);
    const invite = (await (
      await management(d.db, actor, inviteBody)
    ).json()) as { token: string };
    expect(invite.token).toMatch(/^[a-f0-9]{64}$/);
    await expect(
      management(d.db, actor, {
        action: "set_device",
        store_id: id,
        id: device,
        status: "approved",
        reason: "Duyệt",
      }),
    ).rejects.toThrow("chờ đã nhận");
    const claimed = (await (
      await enrollDevice(d.db, {
        token: invite.token,
        installation_id: assignment,
      })
    ).json()) as { device: { status: string; installation_hash?: unknown } };
    expect(claimed.device.status).toBe("pending");
    expect(claimed.device.installation_hash).toBeUndefined();
    await enrollDevice(d.db, {
      token: invite.token,
      installation_id: assignment,
    });
    await expect(
      enrollDevice(d.db, { token: invite.token, installation_id: device }),
    ).rejects.toThrow("bản cài khác");
    await management(d.db, actor, {
      action: "set_device",
      store_id: id,
      id: device,
      status: "approved",
      reason: "Đã kiểm tra máy B3",
    });
    await management(d.db, actor, {
      action: "set_device",
      store_id: id,
      id: device,
      status: "revoked",
      reason: "Ngừng dùng máy",
    });
    await expect(
      management(d.db, actor, {
        action: "set_device",
        store_id: id,
        id: device,
        status: "approved",
        reason: "Dùng lại",
      }),
    ).rejects.toThrow("không được tái sử dụng");
    expect(() =>
      d.sqlite
        .prepare("UPDATE devices SET status='approved' WHERE id=?")
        .run(device),
    ).toThrow("DEVICE_REVOCATION_TERMINAL");
    expect(() =>
      d.sqlite
        .prepare("UPDATE devices SET code='OTHER' WHERE id=?")
        .run(device),
    ).toThrow("DEVICE_IDENTITY_IMMUTABLE");
    const audit = d.sqlite.prepare("SELECT changes_json FROM audit_logs").all();
    expect(JSON.stringify(audit)).not.toContain(invite.token);
  } finally {
    d.sqlite.close();
  }
});
it("Không nâng quyền qua role cũ, không dùng lại mã máy hoặc token quá hạn", async () => {
  const d = fixture();
  try {
    await expect(
      management(d.db, { ...actor, role: "manager" }, storeBody),
    ).rejects.toThrow();
    await expect(
      management(d.db, { ...actor, issued_role: "cashier" }, storeBody),
    ).rejects.toThrow();
    await management(d.db, actor, storeBody);
    const invite = (await (
      await management(d.db, actor, inviteBody)
    ).json()) as { token: string };
    await expect(
      management(d.db, actor, {
        ...inviteBody,
        id: assignment,
        enrollment_id: id,
      }),
    ).rejects.toThrow();
    d.sqlite
      .prepare("UPDATE device_enrollments SET expires_at='2000-01-01'")
      .run();
    await expect(
      enrollDevice(d.db, { token: invite.token, installation_id: assignment }),
    ).rejects.toThrow("hết hạn");
    await expect(
      management(d.db, actor, {
        action: "set_device",
        id: "d1",
        store_id: "s1",
        status: "revoked",
        reason: "Khóa",
      }),
    ).rejects.toThrow("máy đang quản trị");
  } finally {
    d.sqlite.close();
  }
});
it("Gán nhân viên cửa hàng mới không hủy quyền cũ hoặc làm lộ hash mật khẩu", async () => {
  const d = fixture();
  try {
    await management(d.db, actor, storeBody);
    await management(d.db, actor, {
      action: "assign_staff",
      id: device,
      store_id: id,
      user_id: "u2",
      role: "cashier",
      reason: "Làm tại CN02",
    });
    await expect(
      management(d.db, actor, {
        action: "assign_staff",
        id: enrollment,
        store_id: id,
        user_id: "u2",
        role: "manager",
        reason: "Đổi chức vụ",
      }),
    ).rejects.toThrow("đối soát");
    const overview = await (await management(d.db, actor)).text();
    expect(overview).not.toContain("password_hash");
    expect(overview).not.toContain("token_hash");
    expect(
      d.sqlite
        .prepare(
          "SELECT COUNT(*) AS n FROM employee_store_assignments WHERE user_id='u1'",
        )
        .get()?.n,
    ).toBe(2);
  } finally {
    d.sqlite.close();
  }
});
