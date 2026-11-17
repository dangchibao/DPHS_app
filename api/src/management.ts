import type { Actor } from "./auth";
import { auditStatement } from "./audit";
import {
  ApiError,
  checkPermission,
  text,
  randomToken,
  sha256,
  type Role,
} from "./security";

const uuid = (value: unknown) => {
  const id = text(value, "ID client");
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      id,
    )
  )
    throw new ApiError(400, "ID mới phải là UUIDv7 do client sinh.");
  return id;
};
export async function management(
  db: D1Database,
  actor: Actor,
  body?: Record<string, unknown>,
): Promise<Response> {
  checkPermission(actor.role, "configure", actor.issued_role);
  if (!body) {
    const result = await db.batch([
      db.prepare("SELECT * FROM stores ORDER BY code"),
      db.prepare(
        "SELECT id,store_id,code,name,status,created_at,CASE WHEN installation_hash IS NULL THEN 0 ELSE 1 END AS claimed FROM devices ORDER BY store_id,code",
      ),
      db.prepare(
        "SELECT id,username,display_name,active FROM users ORDER BY display_name",
      ),
      db.prepare(
        "SELECT store_id,user_id,role,active FROM employee_store_assignments ORDER BY store_id,user_id",
      ),
    ]);
    return Response.json({
      stores: result[0].results,
      devices: result[1].results,
      users: result[2].results,
      assignments: result[3].results,
    });
  }
  const reason = text(body.reason, "Lý do", 200),
    now = new Date().toISOString();
  if (body.action === "create_store") {
    const id = uuid(body.id),
      code = text(body.code, "Mã chi nhánh", 20).toUpperCase(),
      name = text(body.name, "Tên chi nhánh");
    if (!/^NT-CN[0-9]{2,6}$/.test(code))
      throw new ApiError(400, "Mã cửa hàng dạng NT-CN01.");
    await db.batch([
      db
        .prepare("INSERT INTO stores VALUES (?,?,?,1,?)")
        .bind(id, code, name, now),
      db
        .prepare("INSERT INTO employee_store_assignments VALUES (?,?,?,?,1,?)")
        .bind(uuid(body.assignment_id), id, actor.user_id, "owner", now),
      await auditStatement(db, actor, "STORE_CREATE", id, reason, {
        code,
        name,
      }),
    ]);
    return Response.json({ ok: true, id }, { status: 201 });
  }
  const storeId = text(body.store_id, "Cửa hàng");
  const store = await db
    .prepare("SELECT * FROM stores WHERE id=? AND active=1")
    .bind(storeId)
    .first();
  if (!store)
    throw new ApiError(404, "Không tìm thấy cửa hàng đang hoạt động.");
  if (body.action === "invite_device") {
    const id = uuid(body.id),
      code = text(body.code, "Mã máy", 12).toUpperCase(),
      name = text(body.name, "Tên máy");
    if (!/^[A-Z0-9]{2,12}$/.test(code))
      throw new ApiError(400, "Mã máy gồm 2–12 chữ/số, không tái sử dụng.");
    const token = randomToken(),
      expiry = new Date(Date.now() + 3600000).toISOString();
    await db.batch([
      db
        .prepare(
          "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES (?,?,?,?,'pending',?)",
        )
        .bind(id, storeId, code, name, now),
      db
        .prepare("INSERT INTO device_enrollments VALUES (?,?,?,?,?,?)")
        .bind(
          uuid(body.enrollment_id),
          storeId,
          id,
          await sha256(token),
          now,
          expiry,
        ),
      await auditStatement(db, actor, "DEVICE_INVITE", id, reason, {
        store_id: storeId,
        code,
        name,
        expires_at: expiry,
      }),
    ]);
    return Response.json(
      { ok: true, token, expires_at: expiry, device_id: id },
      { status: 201 },
    );
  }
  if (body.action === "set_device") {
    const id = text(body.id, "Thiết bị"),
      status = body.status;
    if (!["approved", "revoked"].includes(String(status)))
      throw new ApiError(400, "Trạng thái thiết bị không hợp lệ.");
    const device = await db
      .prepare(
        "SELECT status,installation_hash FROM devices WHERE store_id=? AND id=?",
      )
      .bind(storeId, id)
      .first<{ status: string; installation_hash: string | null }>();
    if (!device)
      throw new ApiError(404, "Không tìm thấy thiết bị tại cửa hàng.");
    if (id === actor.device_id)
      throw new ApiError(
        409,
        "Không tự thay đổi trạng thái máy đang quản trị.",
      );
    if (device.status === "revoked")
      throw new ApiError(
        409,
        "Thiết bị đã thu hồi không được tái sử dụng. Hãy đăng ký danh tính mới.",
      );
    if (
      status === "approved" &&
      (!device.installation_hash || device.status !== "pending")
    )
      throw new ApiError(409, "Chỉ duyệt máy chờ đã nhận mã đăng ký.");
    await db.batch([
      db
        .prepare("UPDATE devices SET status=? WHERE store_id=? AND id=?")
        .bind(status, storeId, id),
      db
        .prepare(
          "UPDATE sessions SET revoked=1 WHERE store_id=? AND device_id=?",
        )
        .bind(storeId, id),
      await auditStatement(
        db,
        actor,
        status === "approved" ? "DEVICE_APPROVE" : "DEVICE_REVOKE",
        id,
        reason,
        { store_id: storeId, before: device.status, after: status },
      ),
    ]);
    return Response.json({ ok: true });
  }
  if (body.action === "assign_staff") {
    // Thêm cửa hàng; không hủy quyền cũ khi còn giao dịch offline chưa đối soát.
    const userId = text(body.user_id, "Nhân viên"),
      role = text(body.role, "Vai trò") as Role;
    if (
      !["owner", "manager", "cashier", "warehouse", "accountant"].includes(role)
    )
      throw new ApiError(400, "Vai trò không hợp lệ.");
    if (userId === actor.user_id && role !== "owner")
      throw new ApiError(409, "Không tự hạ quyền chủ đang quản trị.");
    if (
      !(await db
        .prepare("SELECT id FROM users WHERE id=? AND active=1")
        .bind(userId)
        .first())
    )
      throw new ApiError(404, "Nhân viên không tồn tại hoặc đã khóa.");
    const existing = await db
      .prepare(
        "SELECT role,active FROM employee_store_assignments WHERE store_id=? AND user_id=?",
      )
      .bind(storeId, userId)
      .first();
    if (existing)
      throw new ApiError(
        409,
        "Nhân viên đã có phân công; đổi/thu hồi quyền dùng luồng nhân viên và đối soát giao dịch cũ.",
      );
    await db.batch([
      db
        .prepare("INSERT INTO employee_store_assignments VALUES (?,?,?,?,1,?)")
        .bind(uuid(body.id), storeId, userId, role, now),
      await auditStatement(db, actor, "STAFF_ASSIGN_STORE", userId, reason, {
        store_id: storeId,
        role,
      }),
    ]);
    return Response.json({ ok: true }, { status: 201 });
  }
  throw new ApiError(400, "Thao tác quản trị không hợp lệ.");
}

export async function enrollDevice(
  db: D1Database,
  body: Record<string, unknown>,
): Promise<Response> {
  const token = text(body.token, "Mã đăng ký", 64),
    installation = text(body.installation_id, "Mã cài đặt", 100);
  if (!/^[a-f0-9]{64}$/.test(token) || installation.length < 20)
    throw new ApiError(400, "Mã đăng ký/cài đặt không hợp lệ.");
  const enrollment = await db
    .prepare(
      "SELECT e.store_id,e.device_id,d.installation_hash FROM device_enrollments e JOIN stores s ON s.id=e.store_id JOIN devices d ON d.store_id=e.store_id AND d.id=e.device_id WHERE e.token_hash=? AND e.expires_at>? AND s.active=1 AND d.status<>'revoked'",
    )
    .bind(await sha256(token), new Date().toISOString())
    .first<{
      store_id: string;
      device_id: string;
      installation_hash: string | null;
    }>();
  if (!enrollment)
    throw new ApiError(403, "Mã đăng ký sai, hết hạn hoặc máy đã thu hồi.");
  const hash = await sha256(installation);
  const statements = [
    db
      .prepare(
        "UPDATE devices SET installation_hash=? WHERE store_id=? AND id=? AND (installation_hash IS NULL OR installation_hash=?)",
      )
      .bind(hash, enrollment.store_id, enrollment.device_id, hash),
    db
      .prepare("SELECT * FROM devices WHERE store_id=? AND id=?")
      .bind(enrollment.store_id, enrollment.device_id),
    db.prepare("SELECT * FROM stores WHERE id=?").bind(enrollment.store_id),
  ];
  if (!enrollment.installation_hash)
    statements.push(
      await auditStatement(
        db,
        {
          user_id: "",
          store_id: enrollment.store_id,
          device_id: enrollment.device_id,
          role: "cashier",
        },
        "DEVICE_ENROLL",
        enrollment.device_id,
        "Bản cài đã nhận mã đăng ký; chờ chủ duyệt",
      ),
    );
  const result = await db.batch<Record<string, unknown>>(statements);
  const device = result[1].results?.[0];
  if (!device || device.installation_hash !== hash)
    throw new ApiError(409, "Mã đăng ký đã gắn với bản cài khác.");
  const { installation_hash: _, ...publicDevice } = device;
  void _;
  return Response.json({ store: result[2].results?.[0], device: publicDevice });
}
