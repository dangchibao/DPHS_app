import { authenticate, bootstrap, login, staff, challenge } from "./auth";
import { ApiError } from "./security";
import { push, pull } from "./sync";
import { directory } from "./directory";
import { auditStatement } from "./audit";
import { readJsonBody } from "./request";
import { management, enrollDevice } from "./management";
import { minimumSyncSchema } from "./config";
import {
  payrollPreview,
  payrollPull,
  payrollPush,
  syncCheckpoint,
} from "./payroll";
import { passwordHash, constantEqual, credential } from "./security";
export interface Env {
  DB: D1Database;
  ENVIRONMENT: string;
  ALLOWED_ORIGIN: string;
  SESSION_SECRET?: string;
  BOOTSTRAP_PASSWORD?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get("Origin");
    const headers: Record<string, string> = {
      Vary: "Origin",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
    };
    if (origin === env.ALLOWED_ORIGIN) {
      headers["Access-Control-Allow-Origin"] = origin;
      headers["Access-Control-Allow-Headers"] =
        "Authorization, Content-Type, X-Client-Schema";
      headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
    }
    if (request.method === "OPTIONS")
      return new Response(null, { status: 204, headers });
    try {
      const response = await route(request, env);
      for (const [key, value] of Object.entries(headers))
        response.headers.set(key, value);
      return response;
    } catch (error) {
      if (error instanceof ApiError)
        return Response.json(
          { error: error.message, code: error.code },
          { status: error.status, headers },
        );
      const message = String(error);
      if (/STORE_ID_CONFLICT|STORE_REFERENCE_CONFLICT/.test(message))
        return Response.json(
          {
            error: "Dữ liệu hoặc tham chiếu thuộc cửa hàng khác.",
            code: "STORE_CONFLICT",
          },
          { status: 409, headers },
        );
      if (/DEVICE_IDENTITY/.test(message))
        return Response.json(
          {
            error:
              "Thiết bị đã gắn với một máy cài đặt khác. Cần đăng ký thiết bị mới.",
            code: "DEVICE_IDENTITY",
          },
          { status: 409, headers },
        );
      if (
        /exceeded.*(?:row read|row write|daily)|SQLITE_FULL|quota|Error 1027/i.test(
          message,
        )
      )
        return Response.json(
          {
            error: "Cloud đạt giới hạn. Dữ liệu vẫn được giữ trên thiết bị.",
            code: "CLOUD_LIMIT",
          },
          { status: 503, headers },
        );
      if (
        /INSUFFICIENT_STOCK|INSUFFICIENT_DEVICE_ALLOCATION|INSUFFICIENT_AVAILABLE_STOCK/.test(
          message,
        )
      )
        return Response.json(
          {
            error: "Không đủ tồn hoặc phân bổ bán của thiết bị.",
            code: "STOCK_CONFLICT",
          },
          { status: 409, headers },
        );
      if (
        /RECEIVABLE_OVERPAYMENT|PRICE_VERSION_CONFLICT|COMBO_VERSION_CONFLICT|ATTENDANCE_PERIOD_LOCKED/.test(
          message,
        )
      )
        return Response.json(
          {
            error:
              "Công nợ hoặc phiên bản giá cần đối soát. Dữ liệu vẫn được giữ trên thiết bị.",
            code: "BUSINESS_CONFLICT",
          },
          { status: 409, headers },
        );
      if (/VARIANT_PRODUCT_CONFLICT/.test(message))
        return Response.json(
          {
            error:
              "Không đổi sản phẩm gốc của biến thể đã có. Hãy tạo biến thể mới.",
            code: "VARIANT_IDENTITY",
          },
          { status: 409, headers },
        );
      if (
        /UNIQUE constraint failed|FOREIGN KEY constraint failed/.test(message)
      )
        return Response.json(
          {
            error:
              "Mã trùng hoặc dữ liệu liên quan cần đối soát trước khi đồng bộ.",
            code: "DATA_CONFLICT",
          },
          { status: 409, headers },
        );
      return Response.json(
        {
          error: "Không thể xử lý yêu cầu. Dữ liệu chưa được xác nhận.",
          code: "SERVER_ERROR",
        },
        { status: 500, headers },
      );
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname === "/health" && request.method === "GET") {
    await env.DB.prepare("SELECT 1").first();
    return Response.json({
      ok: true,
      service: "Đồng phục Ngọc Thanh",
      schemaVersion: 22,
    });
  }
  const readBody = () => readJsonBody(request);
  if (
    [
      "/directory",
      "/sync/push",
      "/sync/pull",
      "/sync/checkpoint",
      "/payroll/push",
      "/payroll/pull",
      "/payroll/preview",
    ].includes(url.pathname)
  ) {
    const schema = Number(request.headers.get("X-Client-Schema") ?? "0");
    if (!Number.isSafeInteger(schema) || schema < minimumSyncSchema) {
      throw new ApiError(
        401,
        "Cần cập nhật ứng dụng trước khi đồng bộ dữ liệu mới. Dữ liệu đang chờ vẫn được giữ trên máy.",
        "CLIENT_UPGRADE_REQUIRED",
      );
    }
  }
  if (url.pathname === "/devices/enroll" && request.method === "POST")
    return enrollDevice(env.DB, await readBody());
  if (
    url.pathname === "/management" &&
    ["GET", "POST"].includes(request.method)
  )
    return management(
      env.DB,
      await authenticate(request, env, "configure"),
      request.method === "POST" ? await readBody() : undefined,
    );
  if (url.pathname === "/auth/bootstrap" && request.method === "POST")
    return bootstrap(env, await readBody());
  if (url.pathname === "/auth/login" && request.method === "POST")
    return login(env, await readBody(), request);
  if (url.pathname === "/auth/challenge" && request.method === "POST")
    return challenge(env, await readBody(), request);
  if (url.pathname === "/auth/me" && request.method === "GET")
    return Response.json(await authenticate(request, env));
  if (url.pathname === "/directory" && request.method === "GET")
    return directory(env.DB, await authenticate(request, env));
  if (url.pathname === "/sync/checkpoint" && request.method === "POST")
    return syncCheckpoint(
      env.DB,
      await authenticate(request, env),
      await readBody(),
    );
  if (url.pathname === "/payroll/push" && request.method === "POST")
    return payrollPush(
      env.DB,
      await authenticate(request, env, "payroll", "sync"),
      await readBody(),
    );
  if (url.pathname === "/payroll/pull" && request.method === "GET")
    return payrollPull(
      env.DB,
      await authenticate(request, env, "payroll"),
      url,
    );
  if (url.pathname === "/payroll/preview" && request.method === "GET")
    return Response.json(
      await payrollPreview(
        env.DB,
        await authenticate(request, env, "payroll"),
        url.searchParams.get("employee_id"),
        url.searchParams.get("month"),
      ),
    );
  if (url.pathname === "/auth/logout" && request.method === "POST") {
    const actor = await authenticate(request, env);
    await env.DB.batch([
      env.DB.prepare("UPDATE sessions SET revoked=1 WHERE id=?").bind(
        actor.session_id,
      ),
      await auditStatement(env.DB, actor, "LOGOUT", actor.user_id, "Đăng xuất"),
    ]);
    return Response.json({ ok: true });
  }
  if (url.pathname === "/auth/password" && request.method === "POST") {
    const actor = await authenticate(request, env),
      body = await readBody();
    const user = await env.DB.prepare(
      "SELECT password_hash,salt FROM users WHERE id=?",
    )
      .bind(actor.user_id)
      .first<{ password_hash: string; salt: string }>();
    if (
      !user ||
      !constantEqual(
        await passwordHash(credential(body.old_credential), user.salt),
        user.password_hash,
      )
    )
      throw new ApiError(400, "Mật khẩu cũ không đúng.");
    const salt = credential(body.salt),
      hash = await passwordHash(credential(body.credential), salt);
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE users SET password_hash=?,salt=?,must_change_password=0,updated_at=? WHERE id=?",
      ).bind(hash, salt, new Date().toISOString(), actor.user_id),
      env.DB.prepare(
        "UPDATE sessions SET revoked=1 WHERE user_id=? AND id<>?",
      ).bind(actor.user_id, actor.session_id),
      await auditStatement(
        env.DB,
        actor,
        "PASSWORD_CHANGE",
        actor.user_id,
        "Người dùng đổi mật khẩu",
      ),
    ]);
    return Response.json({ ok: true });
  }
  if (url.pathname === "/sync/push" && request.method === "POST")
    return push(
      env.DB,
      await authenticate(request, env, undefined, "sync"),
      await readBody(),
    );
  if (url.pathname === "/sync/pull" && request.method === "GET")
    return pull(env.DB, await authenticate(request, env), url);
  if (url.pathname === "/staff" && ["GET", "POST"].includes(request.method)) {
    const actor = await authenticate(request, env, "staff");
    return staff(
      env,
      actor,
      request.method === "POST" ? await readBody() : undefined,
    );
  }
  return Response.json({ error: "Không tìm thấy chức năng." }, { status: 404 });
}
