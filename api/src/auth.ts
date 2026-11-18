import {
  ApiError,
  checkPermission,
  constantEqual,
  passwordHash,
  randomToken,
  sha256,
  text,
  credential,
} from "./security";
import type { Permission, Role } from "./security";
import type { Env } from "./index";
import { auditStatement, clientAuditHead } from "./audit";
import { staffChangeGate, staffFreezeCondition } from "./staff_handoffs";

export interface Actor {
  user_id: string;
  store_id: string;
  device_id: string;
  role: Role;
  name: string;
  session_id: string;
  issued_role?: Role;
  session_kind?: string;
  device_kind?: string;
  frozen?: number;
}

export async function authenticate(
  request: Request,
  env: Env,
  permission?: Permission,
  purpose: "interactive" | "sync" = "interactive",
): Promise<Actor> {
  const token = request.headers.get("Authorization")?.replace(/^Bearer /, "");
  if (!token || token.length !== 64)
    throw new ApiError(401, "Vui lòng đăng nhập.", "UNAUTHENTICATED");
  const actor = await env.DB.prepare(
    `SELECT s.id AS session_id,s.user_id,s.store_id,s.device_id,a.role,u.display_name AS name,s.kind AS session_kind,s.issued_role,d.kind AS device_kind,${staffFreezeCondition("s.user_id", "s.store_id")} AS frozen
    FROM sessions s JOIN users u ON u.id=s.user_id JOIN employee_store_assignments a ON a.user_id=s.user_id AND a.store_id=s.store_id
    JOIN devices d ON d.id=s.device_id AND d.store_id=s.store_id JOIN stores st ON st.id=s.store_id
    WHERE s.token_hash=? AND s.revoked=0 AND s.expires_at>? AND u.active=1 AND a.active=1 AND d.status='approved' AND st.active=1 AND s.installation_hash=d.installation_hash`,
  )
    .bind(await sha256(token), new Date().toISOString())
    .first<Actor>();
  if (!actor)
    throw new ApiError(
      401,
      "Phiên hết hạn hoặc quyền/thiết bị đã bị thu hồi.",
      "UNAUTHENTICATED",
    );
  if (purpose === "interactive" && actor.session_kind !== "interactive")
    throw new ApiError(
      403,
      "Phiên đồng bộ không được dùng để quản trị.",
      "TOKEN_SCOPE",
    );
  if (permission) checkPermission(actor.role, permission, actor.issued_role);
  if (actor.frozen) {
    const url = new URL(request.url),
      path = url.pathname;
    const drain =
      (purpose === "sync" &&
        ["/sync/push", "/payroll/push", "/staff/handoffs/ack"].includes(
          path,
        )) ||
      (actor.session_kind === "interactive" &&
        (path === "/directory" ||
          path === "/auth/logout" ||
          (path === "/sync/pull" &&
            ["global", "store"].includes(
              url.searchParams.get("scope") ?? "store",
            ))));
    if (!drain)
      throw new ApiError(
        401,
        "Tài khoản đang bàn giao; chỉ đồng bộ giao dịch cũ.",
        "STAFF_HANDOFF_PENDING",
      );
  }
  if (actor.device_kind === "web") {
    const path = new URL(request.url).pathname;
    const allowed = [
      "/auth/me",
      "/auth/logout",
      "/auth/password",
      "/management",
      "/staff",
      "/staff/handoffs",
      "/payroll/pull",
      "/payroll/preview",
      "/web/payroll",
      "/web/catalog",
      "/usage",
      "/audit/read",
      "/audit/options",
    ];
    if (
      purpose === "sync" ||
      (!allowed.includes(path) &&
        !path.startsWith("/reports/") &&
        !path.startsWith("/audit/archives"))
    )
      throw new ApiError(
        403,
        "Trình duyệt chỉ quản lý online; không được bán hoặc đồng bộ giao dịch offline.",
        "WEB_SCOPE",
      );
  }
  return actor;
}

export async function bootstrap(
  env: Env,
  body: Record<string, unknown>,
): Promise<Response> {
  // Bootstrap chỉ local; cloud phải provision bằng script riêng được kiểm soát.
  if (env.ENVIRONMENT !== "development" || !env.BOOTSTRAP_PASSWORD)
    throw new ApiError(403, "Chưa bật khởi tạo local.");
  if (
    !constantEqual(
      typeof body.password === "string" ? body.password : "",
      env.BOOTSTRAP_PASSWORD,
    )
  )
    throw new ApiError(403, "Không thể khởi tạo.");
  const existing = await env.DB.prepare("SELECT id FROM users LIMIT 1").first();
  if (existing) throw new ApiError(409, "Hệ thống đã được khởi tạo.");
  const salt = credential(body.salt),
    hash = await passwordHash(credential(body.credential), salt),
    now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare("INSERT OR IGNORE INTO stores VALUES (?,?,?,?,?)").bind(
      "store-cn01",
      "NT-CN01",
      "Ngọc Thanh · Chi nhánh 01",
      1,
      now,
    ),
    env.DB.prepare(
      "INSERT OR IGNORE INTO devices(id,store_id,code,name,status,created_at) VALUES (?,?,?,?,?,?)",
    ).bind("device-a2", "store-cn01", "A2", "Máy bán hàng A2", "approved", now),
    env.DB.prepare("INSERT INTO users VALUES (?,?,?,?,?,?,?,?)").bind(
      "admin",
      "admin",
      "Chủ hệ thống",
      hash,
      salt,
      1,
      1,
      now,
    ),
    env.DB.prepare(
      "INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?)",
    ).bind(crypto.randomUUID(), "store-cn01", "admin", "owner", 1, now),
    await auditStatement(
      env.DB,
      {
        user_id: "admin",
        store_id: "store-cn01",
        device_id: "device-a2",
        role: "owner",
      },
      "SYSTEM_BOOTSTRAP",
      "admin",
      "Khởi tạo API local",
    ),
  ]);
  return Response.json({ ok: true }, { status: 201 });
}

export async function login(
  env: Env,
  body: Record<string, unknown>,
  request: Request,
  web = false,
): Promise<Response> {
  const username = text(body.username, "Tài khoản", 80),
    proof = credential(body.credential);
  const storeId = text(body.store_id, "Cửa hàng"),
    deviceId = text(body.device_id, "Thiết bị");
  const key = await sha256(
      `${username}|${request.headers.get("CF-Connecting-IP") ?? "local"}`,
    ),
    now = Date.now(),
    window = 15 * 60000;
  const attempts = await env.DB.prepare(
    "SELECT window_start,failures FROM auth_attempts WHERE key=?",
  )
    .bind(key)
    .first<{ window_start: number; failures: number }>();
  if (
    attempts &&
    now - attempts.window_start < window &&
    attempts.failures >= 10
  )
    throw new ApiError(
      429,
      "Đăng nhập sai nhiều lần. Thử lại sau 15 phút.",
      "LOGIN_THROTTLED",
    );
  const user = await env.DB.prepare(
    `SELECT u.*,a.role FROM users u JOIN employee_store_assignments a ON a.user_id=u.id
    JOIN devices d ON d.store_id=a.store_id WHERE u.username=? AND u.active=1 AND a.store_id=? AND a.active=1 AND d.id=? AND d.status='approved' AND d.kind=?`,
  )
    .bind(username, storeId, deviceId, web ? "web" : "native")
    .first<{
      id: string;
      password_hash: string;
      salt: string;
      role: Role;
      display_name: string;
      must_change_password: number;
    }>();
  // Worker chỉ SHA-256, không chạy KDF nặng. Tài khoản không tồn tại
  // cũng đi cùng bước băm/so sánh và cùng thông báo lỗi.
  const hash = await passwordHash(
    proof,
    user?.salt ?? "invalid-account-fixed-salt",
  );
  const legacy = user && !user.password_hash.startsWith("client-v1:");
  const matches =
    user &&
    (legacy
      ? env.ENVIRONMENT === "development" &&
        constantEqual(proof, user.password_hash)
      : constantEqual(hash, user.password_hash));
  if (!matches || !user) {
    const attempt = env.DB.prepare(
      `INSERT INTO auth_attempts VALUES (?,?,1) ON CONFLICT(key) DO UPDATE SET
      failures=CASE WHEN ?-window_start>=? THEN 1 ELSE failures+1 END,
      window_start=CASE WHEN ?-window_start>=? THEN ? ELSE window_start END`,
    ).bind(key, now, now, window, now, window, now);
    const device = await env.DB.prepare(
      "SELECT id FROM devices WHERE store_id=? AND id=?",
    )
      .bind(storeId, deviceId)
      .first();
    await env.DB.batch(
      device
        ? [
            attempt,
            await auditStatement(
              env.DB,
              {
                user_id: "",
                store_id: storeId,
                device_id: deviceId,
                role: "cashier",
              },
              "LOGIN_FAILED",
              "unknown",
              "Sai thông tin đăng nhập",
            ),
          ]
        : [attempt],
    );
    throw new ApiError(
      401,
      "Tài khoản hoặc mật khẩu không đúng.",
      "INVALID_CREDENTIALS",
    );
  }
  if (
    await env.DB.prepare(
      `SELECT 1 FROM employee_store_assignments a WHERE a.user_id=? AND a.store_id=? AND ${staffFreezeCondition("a.user_id", "a.store_id")}`,
    )
      .bind(user.id, storeId)
      .first()
  )
    throw new ApiError(
      403,
      "Tài khoản đang bàn giao. Cần đồng bộ hàng đợi cũ trên các máy trước; quản lý có thể hủy bàn giao để xác thực lại.",
      "STAFF_HANDOFF_PENDING",
    );
  const token = randomToken(),
    syncToken = randomToken(),
    expiresAt = new Date(
      now + (web ? 8 * 3600000 : 7 * 86400000),
    ).toISOString();
  const installation =
    typeof body.installation_id === "string"
      ? text(body.installation_id, "Mã cài đặt")
      : env.ENVIRONMENT === "development"
        ? "local-api-smoke-test"
        : text(undefined, "Mã cài đặt");
  const installationHash = await sha256(installation);
  await env.DB.batch([
    env.DB.prepare("UPDATE users SET password_hash=? WHERE id=?").bind(
      hash,
      user.id,
    ),
    env.DB.prepare(
      "UPDATE devices SET installation_hash=COALESCE(installation_hash,?) WHERE store_id=? AND id=?",
    ).bind(installationHash, storeId, deviceId),
    env.DB.prepare(
      "INSERT INTO sessions(id,store_id,user_id,device_id,token_hash,created_at,expires_at,revoked,installation_hash,kind,issued_role) VALUES (?,?,?,?,?,?,?,0,?,?,?)",
    ).bind(
      crypto.randomUUID(),
      storeId,
      user.id,
      deviceId,
      await sha256(token),
      new Date(now).toISOString(),
      expiresAt,
      installationHash,
      "interactive",
      user.role,
    ),
    ...(!web
      ? [
          env.DB.prepare(
            "INSERT INTO sessions(id,store_id,user_id,device_id,token_hash,created_at,expires_at,revoked,installation_hash,kind,issued_role) VALUES (?,?,?,?,?,?,?,0,?,?,?)",
          ).bind(
            crypto.randomUUID(),
            storeId,
            user.id,
            deviceId,
            await sha256(syncToken),
            new Date(now).toISOString(),
            expiresAt,
            installationHash,
            "sync",
            user.role,
          ),
        ]
      : []),
    env.DB.prepare("DELETE FROM auth_attempts WHERE key=?").bind(key),
    await auditStatement(
      env.DB,
      {
        user_id: user.id,
        store_id: storeId,
        device_id: deviceId,
        role: user.role,
      },
      "LOGIN_SUCCESS",
      user.id,
      "Đăng nhập API",
    ),
  ]);
  return Response.json({
    token,
    ...(web
      ? {}
      : {
          sync_token: syncToken,
          audit_head: await clientAuditHead(env.DB, storeId, deviceId),
        }),
    expires_at: expiresAt,
    user: {
      id: user.id,
      name: user.display_name,
      role: user.role,
      must_change_password: user.must_change_password === 1,
    },
    store_id: storeId,
    device_id: deviceId,
  });
}

export async function challenge(
  env: Env,
  body: Record<string, unknown>,
  request: Request,
): Promise<Response> {
  if (
    env.ENVIRONMENT !== "development" &&
    (!env.SESSION_SECRET || env.SESSION_SECRET.length < 32)
  )
    throw new ApiError(
      503,
      "Cloud chưa cấu hình khóa xác thực.",
      "AUTH_CONFIGURATION",
    );
  const username = text(body.username, "Tài khoản", 80);
  const key = await sha256(
    `${username}|${request.headers.get("CF-Connecting-IP") ?? "local"}`,
  );
  const attempts = await env.DB.prepare(
    "SELECT window_start,failures FROM auth_attempts WHERE key=?",
  )
    .bind(key)
    .first<{ window_start: number; failures: number }>();
  if (
    attempts &&
    Date.now() - attempts.window_start < 15 * 60000 &&
    attempts.failures >= 10
  )
    throw new ApiError(
      429,
      "Đăng nhập sai nhiều lần. Thử lại sau 15 phút.",
      "LOGIN_THROTTLED",
    );
  const user = await env.DB.prepare("SELECT salt FROM users WHERE username=?")
    .bind(username)
    .first<{ salt: string }>();
  return Response.json({
    salt:
      user?.salt ??
      (await sha256(
        `${env.SESSION_SECRET ?? "local-development"}|unknown|${username}`,
      )),
    algorithm: "PBKDF2-SHA256",
    iterations: 600000,
  });
}

export async function staff(
  env: Env,
  actor: Actor,
  body?: Record<string, unknown>,
): Promise<Response> {
  checkPermission(actor.role, "staff", actor.issued_role);
  const owner =
    actor.role === "owner" && (actor.issued_role ?? actor.role) === "owner";
  if (!body) {
    const users = await env.DB.prepare(
      `SELECT u.id,u.username,u.display_name,(u.active AND a.active) AS active,a.role,a.store_id FROM users u
      JOIN employee_store_assignments a ON a.user_id=u.id WHERE a.store_id=? ORDER BY u.display_name`,
    )
      .bind(actor.store_id)
      .all();
    return Response.json({ users: users.results });
  }
  // Quản lý không thể tạo/sửa chủ hoặc sửa quyền của chính mình.
  const role = text(body.role, "Vai trò") as Role;
  if (
    !["owner", "manager", "cashier", "warehouse", "accountant"].includes(role)
  )
    throw new ApiError(400, "Vai trò không hợp lệ.");
  const id = typeof body.id === "string" ? body.id : crypto.randomUUID();
  const target = await env.DB.prepare(
    "SELECT role,active FROM employee_store_assignments WHERE store_id=? AND user_id=?",
  )
    .bind(actor.store_id, id)
    .first<{ role: Role; active: number }>();
  if (
    !owner &&
    (role === "owner" ||
      role === "manager" ||
      target?.role === "owner" ||
      target?.role === "manager" ||
      id === actor.user_id)
  )
    throw new ApiError(403, "Chỉ chủ được thay đổi quyền quản lý.");
  if (id === actor.user_id)
    throw new ApiError(
      400,
      "Không tự thu hồi hoặc thay đổi quyền tài khoản đang dùng.",
    );
  const now = new Date().toISOString(),
    active = body.active === false ? 0 : 1,
    name = text(body.display_name, "Tên nhân viên"),
    username = text(body.username, "Tài khoản", 80);
  const existing = await env.DB.prepare(
    "SELECT id,active FROM users WHERE id=?",
  )
    .bind(id)
    .first<{ id: string; active: number }>();
  const statements: D1PreparedStatement[] = [];
  let requestId: string | undefined;
  if (existing) {
    const gate = await staffChangeGate(env, actor, {
      ...body,
      id,
      role,
      active: active === 1,
      username,
      display_name: name,
    });
    if (gate.response) return gate.response;
    statements.push(...(gate.statements ?? []));
    requestId = gate.requestId;
  }
  if (!existing) {
    const salt = credential(body.salt);
    statements.push(
      env.DB.prepare("INSERT INTO users VALUES (?,?,?,?,?,?,?,?)").bind(
        id,
        username,
        name,
        await passwordHash(credential(body.credential), salt),
        salt,
        active,
        1,
        now,
      ),
    );
  } else {
    if (!target && !owner)
      throw new ApiError(403, "Nhân viên thuộc cửa hàng khác.");
    statements.push(
      env.DB.prepare(
        "UPDATE users SET display_name=?,active=CASE WHEN ?='owner' THEN ? ELSE active END,updated_at=? WHERE id=?",
      ).bind(name, owner ? "owner" : "manager", active, now, id),
    );
  }
  statements.push(
    env.DB.prepare(
      `INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?) ON CONFLICT(store_id,user_id) DO UPDATE SET role=excluded.role,active=excluded.active,updated_at=excluded.updated_at`,
    ).bind(crypto.randomUUID(), actor.store_id, id, role, active, now),
  );
  statements.push(
    env.DB.prepare(
      "UPDATE sessions SET revoked=1 WHERE user_id=? AND ?=1 AND(?=1 OR store_id=?)",
    ).bind(
      id,
      !existing ||
        target?.role !== role ||
        target?.active !== active ||
        (owner && existing.active !== active)
        ? 1
        : 0,
      owner && existing?.active !== active ? 1 : 0,
      actor.store_id,
    ),
  );
  statements.push(
    await auditStatement(
      env.DB,
      actor,
      existing ? "STAFF_UPDATE" : "STAFF_CREATE",
      id,
      text(body.reason, "Lý do"),
      { role, active, display_name: name, request_id: requestId ?? null },
    ),
  );
  await env.DB.batch(statements);
  return Response.json({ ok: true, id });
}
