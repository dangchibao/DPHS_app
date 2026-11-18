import type { Actor } from "./auth";
import { ApiError, checkPermission, sha256, text } from "./security";
import { auditStatement } from "./audit";
import { calculatePayroll, compensationRule } from "./payroll_calculation";
import { utcInstant } from "./reservation_time";

type Row = Record<string, unknown>;
export const payrollTables = [
  "compensation_versions",
  "payroll_runs",
  "payroll_voids",
  "payroll_results",
  "payroll_reconciliations",
];
export const commandColumns = [
  "id",
  "store_id",
  "device_id",
  "user_id",
  "kind",
  "payload_json",
  "created_at",
];
const uuid = (v: unknown) => {
  const id = text(v, "ID client");
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      id,
    )
  )
    throw new ApiError(400, "Cần UUIDv7 do client sinh.");
  return id;
};
export function payrollPeriod(value: unknown) {
  const month = text(value, "Kỳ lương", 7);
  if (
    !/^\d{4}-(0[1-9]|1[0-2])$/.test(month) ||
    month.slice(0, 4) < "2000" ||
    month.slice(0, 4) > "9998"
  )
    throw new ApiError(400, "Kỳ lương dạng YYYY-MM, từ năm 2000.");
  const start = `${month}-01`,
    end = new Date(
      Date.UTC(Number(month.slice(0, 4)), Number(month.slice(5)), 1),
    )
      .toISOString()
      .slice(0, 10);
  return {
    month,
    start,
    end,
    from: new Date(
      Date.parse(`${start}T00:00:00.000Z`) - 7 * 3600000,
    ).toISOString(),
    to: new Date(
      Date.parse(`${end}T00:00:00.000Z`) - 7 * 3600000,
    ).toISOString(),
  };
}
const sourceTypes =
  "entity_type IN ('documents','invoice_lines','return_lines','attendance_entries','attendance_rejections','payments','receivable_entries','receivable_adjustments')";
async function watermark(db: D1Database, store: string, full = false) {
  return (await db
    .prepare(
      `SELECT COALESCE((SELECT server_seq FROM change_feed WHERE store_id=? ${full ? "" : `AND ${sourceTypes}`} ORDER BY server_seq DESC LIMIT 1),0) AS business_seq,COALESCE((SELECT MAX(server_seq) FROM payroll_feed WHERE store_id=?),0) AS private_seq`,
    )
    .bind(store, store)
    .first<{ business_seq: number; private_seq: number }>())!;
}
function feed(db: D1Database, table: string, row: Row) {
  return db
    .prepare(
      "INSERT INTO payroll_feed(store_id,entity_type,entity_id,payload,created_at) VALUES(?,?,?,?,?)",
    )
    .bind(row.store_id, table, row.id, JSON.stringify(row), row.created_at);
}
function insert(db: D1Database, table: string, row: Row) {
  return db
    .prepare(
      `INSERT INTO ${table} (${Object.keys(row).join(",")}) VALUES (${Object.keys(
        row,
      )
        .map(() => "?")
        .join(",")})`,
    )
    .bind(...Object.values(row));
}
function guard(
  db: D1Database,
  id: string,
  store: string,
  seq: { business_seq: number; private_seq: number },
  full = false,
) {
  return db
    .prepare(
      `INSERT INTO payroll_guards SELECT ?,?,?,COALESCE((SELECT server_seq FROM change_feed WHERE store_id=? ${full ? "" : `AND ${sourceTypes}`} ORDER BY server_seq DESC LIMIT 1),0),?,COALESCE((SELECT MAX(server_seq) FROM payroll_feed WHERE store_id=?),0)`,
    )
    .bind(id, store, seq.business_seq, store, seq.private_seq, store);
}
export async function payrollPreview(
  db: D1Database,
  actor: Actor,
  employee: unknown,
  month: unknown,
) {
  checkPermission(actor.role, "payroll", actor.issued_role);
  const employeeId = text(employee, "Nhân viên"),
    period = payrollPeriod(month);
  const before = await watermark(db, actor.store_id);
  const rows = await db.batch<Row>([
    db
      .prepare(
        "SELECT u.id,u.display_name FROM users u JOIN employee_store_assignments a ON a.user_id=u.id WHERE a.store_id=? AND u.id=?",
      )
      .bind(actor.store_id, employeeId),
    db
      .prepare(
        "SELECT * FROM compensation_versions WHERE store_id=? AND employee_id=? AND effective_month<=? ORDER BY effective_month DESC,revision DESC LIMIT 1",
      )
      .bind(actor.store_id, employeeId, period.month),
    db
      .prepare(
        "SELECT CAST(COALESCE(SUM(net_amount),0) AS TEXT) AS net_sales,COUNT(*) AS source_count FROM payroll_sales_source WHERE store_id=? AND employee_id=? AND issued_at>=? AND issued_at<?",
      )
      .bind(actor.store_id, employeeId, period.from, period.to),
    db
      .prepare(
        "WITH ranked AS (SELECT a.*,ROW_NUMBER() OVER(PARTITION BY work_day ORDER BY lww_key DESC,id DESC) AS n FROM attendance_entries a WHERE store_id=? AND employee_id=? AND work_day>=? AND work_day<? AND NOT EXISTS(SELECT 1 FROM attendance_rejections r WHERE r.store_id=a.store_id AND r.id=a.id)) SELECT COALESCE(SUM(day_units),0) AS attendance_units,COUNT(*) AS attendance_days FROM ranked WHERE n=1",
      )
      .bind(actor.store_id, employeeId, period.start, period.end),
    db
      .prepare(
        "SELECT d.id,d.code,d.name,MAX(c.received_at) AS checkpoint FROM devices d LEFT JOIN sync_checkpoints c ON c.store_id=d.store_id AND c.device_id=d.id AND c.received_at>=? WHERE d.store_id=? AND d.status='approved' AND d.kind='native' AND d.created_at<? GROUP BY d.id,d.code,d.name ORDER BY d.code",
      )
      .bind(period.to, actor.store_id, period.to),
    db
      .prepare(
        "SELECT p.id FROM payroll_runs p WHERE p.store_id=? AND p.employee_id=? AND p.period_start=? AND NOT EXISTS(SELECT 1 FROM payroll_voids v WHERE v.store_id=p.store_id AND v.run_id=p.id)",
      )
      .bind(actor.store_id, employeeId, period.start),
  ]);
  if (!rows[0].results.length)
    throw new ApiError(403, "Nhân viên không thuộc cửa hàng.");
  if (!rows[1].results.length)
    throw new ApiError(400, "Chưa có cấu hình lương cho kỳ này.");
  const version = rows[1].results[0],
    config = compensationRule(JSON.parse(version.config_json as string));
  const amount = BigInt(rows[2].results[0].net_sales as string);
  if (
    amount > BigInt(Number.MAX_SAFE_INTEGER) ||
    amount < BigInt(-Number.MAX_SAFE_INTEGER)
  )
    throw new ApiError(400, "Doanh số kỳ vượt giới hạn số nguyên an toàn.");
  const sources = {
    net_sales: Number(amount),
    source_count: rows[2].results[0].source_count,
    attendance_units: rows[3].results[0].attendance_units,
    attendance_days: rows[3].results[0].attendance_days,
  };
  const totals = calculatePayroll(
      config,
      Number(sources.attendance_units),
      sources.net_sales,
    ),
    seq = await watermark(db, actor.store_id);
  if (
    before.business_seq !== seq.business_seq ||
    before.private_seq !== seq.private_seq
  )
    throw new ApiError(409, "Dữ liệu vừa đổi. Tải lại dự tính lương.");
  const quote = {
    employee_id: employeeId,
    employee_name: rows[0].results[0].display_name,
    period_start: period.start,
    period_end: period.end,
    rule_id: version.id,
    config,
    sources,
    totals,
    ...seq,
  };
  return {
    ...quote,
    quote_hash: await sha256(JSON.stringify(quote)),
    devices: rows[4].results,
    active_run: rows[5].results[0]?.id ?? null,
    period_complete: Date.now() >= Date.parse(period.to),
  };
}
export async function payrollViewPreview(
  db: D1Database,
  actor: Actor,
  employee: unknown,
  month: unknown,
) {
  checkPermission(actor.role, "payroll", actor.issued_role);
  const employeeId = text(employee, "Nhân viên"),
    period = payrollPeriod(month);
  await db.batch([
    await auditStatement(
      db,
      actor,
      "PAYROLL_PREVIEW_VIEW",
      employeeId,
      "Đối soát dự tính lương",
      {
        employee_id: employeeId,
        period_start: period.start,
        period_end: period.end,
      },
    ),
  ]);
  return payrollPreview(db, actor, employeeId, period.month);
}
export async function syncCheckpoint(db: D1Database, actor: Actor, body: Row) {
  if (actor.session_kind === "sync")
    throw new ApiError(403, "Cần phiên tương tác để đối soát máy.");
  const now = new Date().toISOString(),
    day = new Date(Date.now() + 7 * 3600000).toISOString().slice(0, 10);
  const existing = await db
    .prepare(
      "SELECT received_at FROM sync_checkpoints WHERE store_id=? AND device_id=? AND day=?",
    )
    .bind(actor.store_id, actor.device_id, day)
    .first();
  if (existing) return Response.json(existing);
  if (body.drained !== true || !Number.isSafeInteger(body.cursor))
    throw new ApiError(
      400,
      "Chỉ đối soát sau khi gửi hết hàng đợi và kéo hết dữ liệu.",
    );
  const seq = await watermark(db, actor.store_id, true);
  if (body.cursor !== seq.business_seq)
    throw new ApiError(
      409,
      "Có dữ liệu mới; cần đồng bộ tiếp trước khi đối soát.",
    );
  const id = crypto.randomUUID();
  await db.batch([
    guard(db, id, actor.store_id, seq, true),
    db
      .prepare("INSERT OR IGNORE INTO sync_checkpoints VALUES(?,?,?,?)")
      .bind(actor.store_id, actor.device_id, day, now),
    db.prepare("DELETE FROM payroll_guards WHERE id=?").bind(id),
  ]);
  return Response.json({ received_at: now });
}
export async function payrollPull(db: D1Database, actor: Actor, url: URL) {
  checkPermission(actor.role, "payroll", actor.issued_role);
  if (actor.session_kind === "sync")
    throw new ApiError(403, "Phiên nền không được đọc dữ liệu lương.");
  const accessKind = `payroll:${new Date(Date.now() + 7 * 3600000).toISOString().slice(0, 10)}`;
  const readMark = () =>
    db
      .prepare(
        "SELECT accessed_at FROM private_access_marks WHERE store_id=? AND session_id=? AND kind=?",
      )
      .bind(actor.store_id, actor.session_id, accessKind)
      .first();
  if (!(await readMark())) {
    try {
      await db.batch([
        db
          .prepare("INSERT INTO private_access_marks VALUES(?,?,?,?)")
          .bind(
            actor.store_id,
            actor.session_id,
            accessKind,
            new Date().toISOString(),
          ),
        await auditStatement(
          db,
          actor,
          "PAYROLL_ACCESS",
          actor.user_id,
          "Truy cập luồng dữ liệu lương đầu phiên/ngày",
          { user_id: actor.user_id, status: "accessed" },
        ),
      ]);
    } catch (error) {
      if (
        !/UNIQUE constraint failed/.test(String(error)) ||
        !(await readMark())
      ) {
        throw error;
      }
    }
  }
  const cursor = Number(url.searchParams.get("cursor") ?? "0");
  if (!Number.isSafeInteger(cursor) || cursor < 0)
    throw new ApiError(400, "Cursor không hợp lệ.");
  const result = await db
    .prepare(
      "SELECT * FROM payroll_feed WHERE store_id=? AND server_seq>? ORDER BY server_seq LIMIT 100",
    )
    .bind(actor.store_id, cursor)
    .all<Row>();
  return Response.json({
    events: result.results,
    cursor: result.results.at(-1)?.server_seq ?? cursor,
    has_more: result.results.length === 100,
  });
}
export async function payrollPush(db: D1Database, actor: Actor, body: Row) {
  checkPermission(actor.role, "payroll", actor.issued_role);
  const mutations = body.mutations;
  if (!Array.isArray(mutations) || mutations.length !== 1)
    throw new ApiError(400, "Mỗi request ghi một yêu cầu lương.");
  const mutation = mutations[0];
  uuid(mutation.id);
  if (
    !Array.isArray(mutation.records) ||
    mutation.records.length !== 1 ||
    mutation.records[0].table !== "payroll_commands"
  )
    throw new ApiError(400, "Yêu cầu lương không hợp lệ.");
  const row = mutation.records[0].row as Row;
  if (
    !row ||
    Object.keys(row).length !== commandColumns.length ||
    commandColumns.some((k) => !Object.hasOwn(row, k))
  )
    throw new ApiError(400, "Trường yêu cầu lương không hợp lệ.");
  const id = uuid(row.id);
  if (
    row.store_id !== actor.store_id ||
    row.device_id !== actor.device_id ||
    row.user_id !== actor.user_id
  )
    throw new ApiError(403, "Sai cửa hàng, người hoặc máy lập yêu cầu lương.");
  if (utcInstant(row.created_at, "Thời điểm lập") > Date.now() + 300000)
    throw new ApiError(400, "Đồng hồ thiết bị vượt thời gian server.");
  text(row.payload_json, "Dữ liệu lương", 16000);
  const hash = await sha256(
    JSON.stringify(Object.fromEntries(commandColumns.map((k) => [k, row[k]]))),
  );
  const existing = await db
    .prepare("SELECT * FROM payroll_results WHERE id=?")
    .bind(id)
    .first<Row>();
  const response = (result: Row) =>
    Response.json({
      acknowledged: [mutation.id],
      outcomes: [
        {
          id,
          status: result.status,
          message: result.message,
          created_at: result.created_at,
        },
      ],
    });
  if (existing) {
    if (
      existing.store_id !== actor.store_id ||
      existing.device_id !== actor.device_id ||
      existing.user_id !== actor.user_id
    )
      throw new ApiError(403, "Yêu cầu thuộc danh tính khác.");
    if (existing.record_hash !== hash)
      throw new ApiError(409, "ID yêu cầu đã dùng cho nội dung khác.");
    return response(existing);
  }
  const now = new Date().toISOString(),
    result: Row = {
      id,
      store_id: actor.store_id,
      device_id: actor.device_id,
      user_id: actor.user_id,
      record_hash: hash,
      status: "accepted",
      message: "Đã xác nhận",
      created_at: now,
    };
  try {
    let payload: Row;
    try {
      payload = JSON.parse(row.payload_json as string) as Row;
    } catch {
      throw new ApiError(400, "Nội dung yêu cầu không phải JSON hợp lệ.");
    }
    if (!payload || typeof payload !== "object" || Array.isArray(payload))
      throw new ApiError(400, "Nội dung yêu cầu không hợp lệ.");
    let seq = await watermark(db, actor.store_id);
    const statements: D1PreparedStatement[] = [];
    if (row.kind === "rule") {
      const employee = text(payload.employee_id, "Nhân viên"),
        period = payrollPeriod(payload.effective_month),
        config = compensationRule(payload.config);
      if (
        !(await db
          .prepare(
            "SELECT id FROM employee_store_assignments WHERE store_id=? AND user_id=?",
          )
          .bind(actor.store_id, employee)
          .first())
      )
        throw new ApiError(400, "Nhân viên không thuộc cửa hàng.");
      const prior = await db
        .prepare(
          "SELECT id,revision FROM compensation_versions WHERE store_id=? AND employee_id=? AND effective_month=? ORDER BY revision DESC LIMIT 1",
        )
        .bind(actor.store_id, employee, period.month)
        .first<{ id: string; revision: number }>();
      if ((payload.previous_id ?? null) !== (prior?.id ?? null))
        throw new ApiError(
          409,
          "Cấu hình đã đổi trên máy khác. Tải lại và tạo yêu cầu mới.",
        );
      const version: Row = {
        id,
        store_id: actor.store_id,
        device_id: actor.device_id,
        user_id: actor.user_id,
        employee_id: employee,
        effective_month: period.month,
        revision: (prior?.revision ?? 0) + 1,
        previous_id: prior?.id ?? null,
        config_json: JSON.stringify(config),
        created_at: now,
      };
      statements.push(
        insert(db, "compensation_versions", version),
        feed(db, "compensation_versions", version),
      );
    } else if (row.kind === "issue") {
      const quote = await payrollPreview(
        db,
        actor,
        payload.employee_id,
        payload.month,
      );
      if (payload.quote_hash !== quote.quote_hash)
        throw new ApiError(
          409,
          "Nguồn lương đã đổi. Xem lại dự tính trước khi chốt.",
        );
      if (!quote.period_complete)
        throw new ApiError(400, "Chưa kết thúc tháng; chỉ được xem dự tính.");
      if (quote.active_run)
        throw new ApiError(
          409,
          "Kỳ đã chốt; cần hủy phiếu cũ trước khi phát hành lại.",
        );
      if (quote.devices.some((d) => !d.checkpoint))
        throw new ApiError(
          409,
          "Còn máy chưa gửi hết dữ liệu sau khi kết thúc kỳ.",
        );
      if (payload.confirm_reconciled !== true)
        throw new ApiError(
          400,
          "Cần xác nhận đã đối soát các máy, kể cả máy thu hồi.",
        );
      seq = {
        business_seq: quote.business_seq,
        private_seq: quote.private_seq,
      };
      const run: Row = {
        id,
        store_id: actor.store_id,
        device_id: actor.device_id,
        user_id: actor.user_id,
        employee_id: quote.employee_id,
        employee_name: quote.employee_name,
        period_start: quote.period_start,
        period_end: quote.period_end,
        rule_id: quote.rule_id,
        config_json: JSON.stringify(quote.config),
        sources_json: JSON.stringify(quote.sources),
        totals_json: JSON.stringify(quote.totals),
        ...seq,
        created_at: now,
      };
      const lock: Row = {
        id,
        store_id: actor.store_id,
        employee_id: quote.employee_id,
        run_id: id,
        period_start: quote.period_start,
        period_end: quote.period_end,
        created_at: now,
      };
      statements.push(
        insert(db, "payroll_runs", run),
        feed(db, "payroll_runs", run),
        insert(db, "payroll_locks", lock),
        db
          .prepare(
            "INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) VALUES(?,?,'payroll_locks',?,?,?)",
          )
          .bind(actor.store_id, id, id, JSON.stringify(lock), now),
      );
    } else if (row.kind === "void") {
      const runId = text(payload.run_id, "Phiếu lương"),
        reason = text(payload.reason, "Lý do hủy", 200);
      if (
        !(await db
          .prepare("SELECT id FROM payroll_runs WHERE store_id=? AND id=?")
          .bind(actor.store_id, runId)
          .first())
      )
        throw new ApiError(400, "Không tìm thấy phiếu lương.");
      if (
        await db
          .prepare("SELECT id FROM payroll_voids WHERE store_id=? AND run_id=?")
          .bind(actor.store_id, runId)
          .first()
      )
        throw new ApiError(409, "Phiếu lương đã hủy.");
      const event: Row = {
        id,
        store_id: actor.store_id,
        device_id: actor.device_id,
        user_id: actor.user_id,
        run_id: runId,
        reason,
        created_at: now,
      };
      const release: Row = {
        id,
        store_id: actor.store_id,
        run_id: runId,
        created_at: now,
      };
      statements.push(
        insert(db, "payroll_voids", event),
        feed(db, "payroll_voids", event),
        insert(db, "payroll_lock_releases", release),
        db
          .prepare(
            "INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) VALUES(?,?,'payroll_lock_releases',?,?,?)",
          )
          .bind(actor.store_id, id, id, JSON.stringify(release), now),
      );
    } else throw new ApiError(400, "Loại yêu cầu lương không hợp lệ.");
    await db.batch([
      guard(db, id, actor.store_id, seq),
      ...statements,
      insert(db, "payroll_results", result),
      feed(db, "payroll_results", result),
      await auditStatement(
        db,
        actor,
        `PAYROLL_${String(row.kind).toUpperCase()}`,
        id,
        "Xác nhận yêu cầu lương",
        { command_id: id, status: "accepted" },
      ),
      db.prepare("DELETE FROM payroll_guards WHERE id=?").bind(id),
    ]);
  } catch (error) {
    const guardRace = /CHECK constraint failed|UNIQUE constraint failed/.test(
      String(error),
    );
    if (!(error instanceof ApiError) || ![400, 409].includes(error.status)) {
      if (!guardRace) throw error;
    }
    result.status = "rejected";
    result.message = guardRace
      ? "Dữ liệu đổi trong lúc xử lý. Tải lại và lập yêu cầu mới."
      : (error as ApiError).message;
    await db.batch([
      insert(db, "payroll_results", result),
      feed(db, "payroll_results", result),
      await auditStatement(
        db,
        actor,
        "PAYROLL_REJECTED",
        id,
        "Yêu cầu lương không được áp dụng",
        { command_id: id, status: "rejected" },
      ),
    ]);
  }
  return response(result);
}
