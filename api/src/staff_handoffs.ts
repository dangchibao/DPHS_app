import type { Actor } from "./auth";
import type { Env } from "./index";
import { ApiError, checkPermission, text } from "./security";
import { auditStatement } from "./audit";
type Row = Record<string, unknown>;
export const staffFreezeCondition = (user: string, store: string) =>
  `(EXISTS(SELECT 1 FROM staff_change_requests h WHERE h.store_id=${store} AND h.user_id=${user} AND h.status='pending') OR EXISTS(SELECT 1 FROM staff_change_requests h WHERE h.global_lock=1 AND h.user_id=${user} AND h.status='pending'))`;
const uuid = (v: unknown) => {
  const id = text(v, "ID bàn giao");
  if (
    !/^[a-f0-9]{8}-[a-f0-9]{4}-7[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(
      id,
    )
  )
    throw new ApiError(400, "Cần UUIDv7 do client sinh.");
  return id;
};
async function snapshot(
  db: D1Database,
  user: string,
  store: string,
  global: boolean,
) {
  const [u, a] = await db.batch<Row>([
    db
      .prepare(
        "SELECT active,display_name,must_change_password,updated_at FROM users WHERE id=?",
      )
      .bind(user),
    db
      .prepare(
        "SELECT store_id,role,active,updated_at FROM employee_store_assignments WHERE user_id=? AND (?=1 OR store_id=?) ORDER BY store_id",
      )
      .bind(user, global ? 1 : 0, store),
  ]);
  return { user: u.results[0], assignments: a.results };
}
function publicRequest(row: Row) {
  return {
    id: row.id,
    store_id: row.store_id,
    user_id: row.user_id,
    status: row.status,
    created_at: row.created_at,
    global_lock: row.global_lock,
    payload: JSON.parse(row.payload_json as string),
  };
}

export async function staffChangeGate(
  env: Env,
  actor: Actor,
  body: Row,
): Promise<{
  response?: Response;
  statements?: D1PreparedStatement[];
  requestId?: string;
}> {
  const db = env.DB,
    user = text(body.id, "Nhân viên"),
    role = text(body.role, "Vai trò"),
    active = body.active === false ? 0 : 1;
  const payload = {
    id: user,
    username: text(body.username, "Tài khoản", 80),
    display_name: text(body.display_name, "Tên"),
    role,
    active: active === 1,
    reason: text(body.reason, "Lý do", 200),
  };
  const encoded = JSON.stringify(payload);
  let request: Row | null = null;
  if (body.change_request) {
    request = await db
      .prepare(
        "SELECT * FROM staff_change_requests WHERE id=? AND store_id=? AND user_id=?",
      )
      .bind(text(body.change_request, "Yêu cầu"), actor.store_id, user)
      .first<Row>();
    if (!request || request.payload_json !== encoded)
      throw new ApiError(409, "Yêu cầu bàn giao không khớp hồ sơ.");
    if (request.global_lock === 1)
      checkPermission(actor.role, "configure", actor.issued_role);
    if (request.status === "completed")
      return { response: Response.json({ ok: true, id: user }) };
    if (request.status !== "pending")
      throw new ApiError(409, "Yêu cầu bàn giao đã hủy.");
    if (body.confirmed !== true)
      throw new ApiError(400, "Cần xác nhận đã bàn giao.");
  } else {
    const current = await snapshot(db, user, actor.store_id, false),
      assignment = current.assignments[0];
    if (!current.user) return {};
    const global =
      actor.role === "owner" &&
      (actor.issued_role ?? actor.role) === "owner" &&
      active === 0 &&
      current.user.active === 1;
    const existing = await db
      .prepare(
        "SELECT * FROM staff_change_requests WHERE user_id=? AND status='pending' AND(global_lock=1 OR ?=1 OR store_id=?) LIMIT 1",
      )
      .bind(user, global ? 1 : 0, actor.store_id)
      .first<Row>();
    if (existing) {
      if (existing.global_lock === 1)
        checkPermission(actor.role, "configure", actor.issued_role);
      if (existing.store_id !== actor.store_id && actor.role !== "owner")
        throw new ApiError(409, "Nhân viên đang bàn giao toàn hệ thống.");
      return {
        response: Response.json(
          { handoff_required: true, request: publicRequest(existing) },
          { status: 202 },
        ),
      };
    }
    if (
      !global &&
      (!assignment ||
        (assignment.role === role && assignment.active === active))
    )
      return {};
    const pinned = await snapshot(db, user, actor.store_id, global);
    const scopes = global
      ? pinned.assignments
          .filter((a) => a.active === 1)
          .map((a) => a.store_id as string)
      : [actor.store_id];
    const count = await db
      .prepare(
        "SELECT COUNT(*) AS n FROM devices d WHERE d.kind='native' AND d.store_id IN(SELECT value FROM json_each(?)) AND (d.status='approved' OR d.status='revoked' AND EXISTS(SELECT 1 FROM sessions s WHERE s.store_id=d.store_id AND s.device_id=d.id))",
      )
      .bind(JSON.stringify(scopes))
      .first<{ n: number }>();
    if (!count?.n) return {};
    const id = uuid(body.change_id),
      now = new Date().toISOString();
    await db.batch([
      db
        .prepare(
          "INSERT INTO staff_change_guards SELECT ?,?,NOT EXISTS(SELECT 1 FROM staff_change_requests WHERE user_id=? AND status='pending' AND(global_lock=1 OR ?=1 OR store_id=?))",
        )
        .bind(id, actor.store_id, user, global ? 1 : 0, actor.store_id),
      db
        .prepare(
          "INSERT INTO staff_change_requests VALUES(?,?,?,?,?,?,?,?,?,'pending',?,NULL)",
        )
        .bind(
          id,
          actor.store_id,
          user,
          actor.device_id,
          actor.user_id,
          global ? 1 : 0,
          JSON.stringify(scopes),
          encoded,
          JSON.stringify(pinned),
          now,
        ),
      db
        .prepare(
          "INSERT INTO staff_change_devices SELECT store_id,?,id,NULL,NULL FROM devices d WHERE d.kind='native' AND d.store_id IN(SELECT value FROM json_each(?)) AND(d.status='approved' OR d.status='revoked' AND EXISTS(SELECT 1 FROM sessions s WHERE s.store_id=d.store_id AND s.device_id=d.id))",
        )
        .bind(id, JSON.stringify(scopes)),
      await auditStatement(
        db,
        actor,
        "STAFF_HANDOFF_PREPARE",
        user,
        payload.reason,
        { request_id: id, role, active, stores: scopes },
      ),
      db.prepare("DELETE FROM staff_change_guards WHERE id=?").bind(id),
    ]);
    return {
      response: Response.json(
        { handoff_required: true, request: { id, status: "pending" } },
        { status: 202 },
      ),
    };
  }
  const pinned = await snapshot(
    db,
    user,
    actor.store_id,
    request.global_lock === 1,
  );
  if (JSON.stringify(pinned) !== request.snapshot_json)
    throw new ApiError(
      409,
      "Hồ sơ đã đổi trong lúc bàn giao; hủy yêu cầu cũ rồi tạo lại.",
    );
  if (
    await db
      .prepare(
        "SELECT device_id FROM staff_change_devices WHERE request_id=? AND acked_at IS NULL LIMIT 1",
      )
      .bind(request.id)
      .first()
  )
    throw new ApiError(409, "Còn máy chưa dừng quyền cũ/gửi hết hàng đợi.");
  const id = request.id as string;
  // Recheck all versions/acks inside the same transaction as staff updates.
  const guard = db
    .prepare(
      `INSERT INTO staff_change_guards SELECT ?,?,
 EXISTS(SELECT 1 FROM staff_change_requests h WHERE h.id=? AND h.status='pending'
 AND NOT EXISTS(SELECT 1 FROM staff_change_devices d WHERE d.request_id=h.id AND d.acked_at IS NULL)
 AND EXISTS(SELECT 1 FROM users u WHERE u.id=h.user_id AND json_object('active',u.active,'display_name',u.display_name,'must_change_password',u.must_change_password,'updated_at',u.updated_at)=json_extract(h.snapshot_json,'$.user'))
 AND NOT EXISTS(SELECT 1 FROM json_each(h.snapshot_json,'$.assignments') j LEFT JOIN employee_store_assignments a ON a.store_id=json_extract(j.value,'$.store_id') AND a.user_id=h.user_id WHERE a.id IS NULL OR a.role<>json_extract(j.value,'$.role') OR a.active<>json_extract(j.value,'$.active') OR a.updated_at<>json_extract(j.value,'$.updated_at'))
 AND (SELECT COUNT(*) FROM employee_store_assignments a WHERE a.user_id=h.user_id AND(h.global_lock=1 OR a.store_id=h.store_id))=json_array_length(h.snapshot_json,'$.assignments'))`,
    )
    .bind(id, actor.store_id, id);
  return {
    requestId: id,
    statements: [
      guard,
      db
        .prepare(
          "UPDATE staff_change_requests SET status='completed',closed_at=? WHERE id=? AND status='pending'",
        )
        .bind(new Date().toISOString(), id),
      db.prepare("DELETE FROM staff_change_guards WHERE id=?").bind(id),
    ],
  };
}

export async function handoffRequests(
  db: D1Database,
  actor: Actor,
  body?: Row,
  apply?: (body: Row) => Promise<Response>,
): Promise<Response> {
  checkPermission(actor.role, "staff", actor.issued_role);
  const owner =
    actor.role === "owner" && (actor.issued_role ?? actor.role) === "owner";
  if (!body) {
    const requests = await db
      .prepare(
        "SELECT h.*,u.display_name FROM staff_change_requests h JOIN users u ON u.id=h.user_id WHERE(h.store_id=? OR ?='owner') AND(h.global_lock=0 OR ?='owner') ORDER BY h.created_at DESC,h.id DESC LIMIT 50",
      )
      .bind(
        actor.store_id,
        owner ? "owner" : "manager",
        owner ? "owner" : "manager",
      )
      .all<Row>();
    const devices = await db
      .prepare(
        "SELECT d.*,v.code,v.name,v.status AS device_status,s.code AS store_code FROM staff_change_devices d JOIN devices v ON v.store_id=d.store_id AND v.id=d.device_id JOIN stores s ON s.id=d.store_id JOIN staff_change_requests h ON h.id=d.request_id WHERE(h.store_id=? OR ?='owner') AND(h.global_lock=0 OR ?='owner') AND h.status='pending' ORDER BY s.code,v.code",
      )
      .bind(
        actor.store_id,
        owner ? "owner" : "manager",
        owner ? "owner" : "manager",
      )
      .all();
    return Response.json({
      store_id: actor.store_id,
      requests: requests.results.map((r) => ({
        ...publicRequest(r),
        name: r.display_name,
      })),
      devices: devices.results,
    });
  }
  const id = text(body.id, "Yêu cầu"),
    request = await db
      .prepare("SELECT * FROM staff_change_requests WHERE id=?")
      .bind(id)
      .first<Row>();
  if (!request || request.store_id !== actor.store_id)
    throw new ApiError(403, "Đăng nhập đúng cửa hàng tạo yêu cầu để xử lý.");
  if (request.global_lock === 1)
    checkPermission(actor.role, "configure", actor.issued_role);
  const desired = JSON.parse(request.payload_json as string) as Row;
  const target = await db
    .prepare(
      "SELECT role FROM employee_store_assignments WHERE store_id=? AND user_id=?",
    )
    .bind(request.store_id, request.user_id)
    .first<{ role: string }>();
  if (
    !owner &&
    (["owner", "manager"].includes(String(desired.role)) ||
      ["owner", "manager"].includes(target?.role ?? "") ||
      request.user_id === actor.user_id)
  )
    throw new ApiError(403, "Chỉ chủ được xử lý bàn giao quyền quản lý.");
  if (body.action === "commit" && apply)
    return apply({
      ...JSON.parse(request.payload_json as string),
      change_request: id,
      confirmed: body.confirmed,
    });
  if (body.action === "cancel" && request.status === "cancelled")
    return Response.json({ ok: true });
  if (body.action !== "cancel" || request.status !== "pending")
    throw new ApiError(409, "Yêu cầu không còn chờ bàn giao.");
  const reason = text(body.reason, "Lý do hủy", 200);
  await db.batch([
    db
      .prepare(
        "INSERT INTO staff_change_guards SELECT ?,?,EXISTS(SELECT 1 FROM staff_change_requests WHERE id=? AND status='pending')",
      )
      .bind(id, actor.store_id, id),
    db
      .prepare(
        "UPDATE staff_change_requests SET status='cancelled',closed_at=? WHERE id=? AND status='pending'",
      )
      .bind(new Date().toISOString(), id),
    db
      .prepare(
        "UPDATE sessions SET revoked=1 WHERE user_id=? AND kind='interactive' AND(?=1 OR store_id=?)",
      )
      .bind(request.user_id, request.global_lock, request.store_id),
    await auditStatement(
      db,
      actor,
      "STAFF_HANDOFF_CANCEL",
      request.user_id as string,
      reason,
      { request_id: id },
    ),
    db.prepare("DELETE FROM staff_change_guards WHERE id=?").bind(id),
  ]);
  return Response.json({ ok: true });
}
export async function handoffAck(
  db: D1Database,
  actor: Actor,
  body: Row,
): Promise<Response> {
  const id = text(body.id, "Yêu cầu");
  if (
    actor.device_kind === "web" ||
    body.drained !== true ||
    !Number.isSafeInteger(body.cursor)
  )
    throw new ApiError(
      400,
      "Chỉ máy native đã gửi hết hàng đợi được xác nhận.",
    );
  const found = await db
    .prepare(
      "SELECT d.acked_at FROM staff_change_devices d JOIN staff_change_requests h ON h.id=d.request_id WHERE d.store_id=? AND d.device_id=? AND d.request_id=? AND h.status='pending'",
    )
    .bind(actor.store_id, actor.device_id, id)
    .first<Row>();
  if (!found) throw new ApiError(403, "Không có yêu cầu chờ trên máy này.");
  if (found.acked_at) return Response.json({ ok: true });
  const now = new Date().toISOString();
  await db.batch([
    db
      .prepare(
        "INSERT INTO staff_change_guards SELECT ?,?,?=COALESCE((SELECT server_seq FROM change_feed WHERE store_id=? ORDER BY server_seq DESC LIMIT 1),0)",
      )
      .bind(id, actor.store_id, body.cursor, actor.store_id),
    db
      .prepare(
        "UPDATE staff_change_devices SET acked_at=?,cursor=? WHERE store_id=? AND device_id=? AND request_id=? AND acked_at IS NULL",
      )
      .bind(now, body.cursor, actor.store_id, actor.device_id, id),
    db.prepare("DELETE FROM staff_change_guards WHERE id=?").bind(id),
  ]);
  return Response.json({ ok: true });
}
