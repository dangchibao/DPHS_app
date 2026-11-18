import { auditRecordDigest } from "./audit_archive_format";
import { ApiError, checkPermission, money, sha256, text } from "./security";
import type { Actor } from "./auth";
import { validateSales } from "./sales";
import { auditStatement } from "./audit";
import { validateCollections } from "./collections";
import { validateComboRule } from "./combos";
import { validateCommercialRule } from "./commercial";
import { validateTailorRule, validateTailorEvents } from "./tailoring";
import { validateReturns } from "./returns";
import { validateReservations } from "./reservations";
import { validateSizeRule } from "./sizes";
import { validateTransfers } from "./transfers";
import { redactAuditChanges } from "./audit_redaction";
import {
  attendanceColumns,
  attendanceFeedTypes,
  validateAttendance,
} from "./attendance";
import { rolePermissions } from "./security";
import { cloudBudget, syncLimits } from "./config";
import { reportProjection } from "./report_projection";
import { bankConfig } from "./bank_account";

export function recordJsonExpression(
  columns: readonly string[],
  prefix = "",
): string {
  const first = Math.floor(cloudBudget.d1FunctionArguments / 2),
    rest = Math.floor((cloudBudget.d1FunctionArguments - 1) / 2);
  let result = `json_object(${columns
    .slice(0, first)
    .map((c) => `'${c}',${prefix}${c}`)
    .join(",")})`;
  for (let i = first; i < columns.length; i += rest) {
    result = `json_set(${result},${columns
      .slice(i, i + rest)
      .map((c) => `'$.${c}',${prefix}${c}`)
      .join(",")})`;
  }
  return result;
}

export const entityColumns: Record<string, readonly string[]> = {
  stock_threshold_rules: [
    "id",
    "store_id",
    "device_id",
    "user_id",
    "variant_id",
    "threshold",
    "version_key",
    "created_at",
  ],
  bank_accounts: [
    "id",
    "store_id",
    "device_id",
    "user_id",
    "config_json",
    "updated_at",
    "lww_key",
  ],
  attendance_entries: attendanceColumns,
  transfer_events: [
    "id",
    "store_id",
    "device_id",
    "document_id",
    "user_id",
    "reason",
    "created_at",
  ],
  transfer_receipts: [
    "id",
    "store_id",
    "device_id",
    "offer_id",
    "user_id",
    "counts_json",
    "reason",
    "created_at",
  ],
  size_rules: [
    "id",
    "store_id",
    "product_id",
    "name",
    "config_json",
    "active",
    "updated_at",
    "lww_key",
  ],
  reservation_lines: [
    "id",
    "store_id",
    "device_id",
    "document_id",
    "variant_id",
    "quantity",
    "expires_at",
    "created_at",
  ],
  reservation_events: [
    "id",
    "store_id",
    "device_id",
    "document_id",
    "kind",
    "related_document_id",
    "user_id",
    "reason",
    "created_at",
  ],
  return_lines: [
    "id",
    "store_id",
    "document_id",
    "original_line_id",
    "quantity",
    "credit",
    "base_returned",
  ],
  receivable_adjustments: [
    "id",
    "store_id",
    "customer_id",
    "document_id",
    "credit_document_id",
    "amount",
    "created_at",
  ],
  tailoring_rules: [
    "id",
    "store_id",
    "name",
    "config_json",
    "active",
    "updated_at",
    "lww_key",
  ],
  document_events: [
    "id",
    "store_id",
    "document_id",
    "type",
    "related_id",
    "reason",
    "user_id",
    "created_at",
  ],
  commercial_rules: [
    "id",
    "store_id",
    "name",
    "kind",
    "config_json",
    "active",
    "updated_at",
    "lww_key",
  ],
  combo_rules: [
    "id",
    "store_id",
    "name",
    "price",
    "items_json",
    "active",
    "updated_at",
    "lww_key",
  ],
  schools: [
    "id",
    "store_id",
    "name",
    "level",
    "customer_id",
    "active",
    "updated_at",
    "lww_key",
  ],
  school_classes: [
    "id",
    "store_id",
    "school_id",
    "name",
    "academic_year",
    "active",
    "updated_at",
    "lww_key",
  ],
  students: [
    "id",
    "store_id",
    "class_id",
    "student_code",
    "name",
    "customer_id",
    "active",
    "updated_at",
    "lww_key",
  ],
  products: [
    "id",
    "name",
    "category",
    "gender",
    "school_level",
    "school_year",
    "image_path",
    "active",
    "updated_at",
    "version",
    "lww_key",
  ],
  product_variants: [
    "id",
    "product_id",
    "sku",
    "barcode",
    "size",
    "color",
    "unit",
    "cost",
    "price",
    "active",
    "updated_at",
    "version",
    "lww_key",
  ],
  stock_movements: [
    "id",
    "store_id",
    "device_id",
    "variant_id",
    "quantity",
    "kind",
    "document_id",
    "reason",
    "user_id",
    "created_at",
  ],
  audit_logs: [
    "id",
    "store_id",
    "device_id",
    "user_id",
    "role",
    "action",
    "entity_type",
    "entity_id",
    "document_code",
    "changes_json",
    "reason",
    "client_time",
    "server_time",
    "app_version",
    "severity",
    "hash_prev",
    "hash",
    "chain_index",
  ],
  customers: [
    "id",
    "store_id",
    "name",
    "phone",
    "kind",
    "updated_at",
    "lww_key",
  ],
  documents: [
    "id",
    "store_id",
    "device_id",
    "type",
    "kind",
    "code",
    "issued_at",
    "user_id",
    "customer_id",
    "original_id",
    "subtotal",
    "discount",
    "total",
    "school_year",
    "metadata_json",
  ],
  invoice_lines: [
    "id",
    "store_id",
    "document_id",
    "variant_id",
    "name",
    "size",
    "color",
    "unit",
    "quantity",
    "unit_price",
    "unit_cost",
    "discount",
    "price_version",
  ],
  payments: [
    "id",
    "store_id",
    "device_id",
    "document_id",
    "user_id",
    "amount",
    "method",
    "direction",
    "created_at",
    "note",
  ],
  receivable_entries: [
    "id",
    "store_id",
    "customer_id",
    "document_id",
    "payment_id",
    "amount",
    "due_date",
    "created_at",
  ],
};
export interface SyncRecord {
  table: string;
  row: Record<string, unknown>;
}
interface Mutation {
  id: string;
  records: SyncRecord[];
}
const mutableTables = new Set([
  "bank_accounts",
  "size_rules",
  "tailoring_rules",
  "commercial_rules",
  "combo_rules",
  "products",
  "product_variants",
  "customers",
  "schools",
  "school_classes",
  "students",
]);

function validateRecord(
  record: SyncRecord,
  actor: Actor,
  sales: Set<string>,
  returns: Set<string> = new Set(),
  transfers: Set<string> = new Set(),
): void {
  const columns = entityColumns[record.table];
  if (!columns || !record.row || typeof record.row !== "object")
    throw new ApiError(400, "Loại dữ liệu đồng bộ không hợp lệ.");
  const row = record.row;
  for (const key of Object.keys(row))
    if (!columns.includes(key))
      throw new ApiError(400, `Trường không được phép: ${key}`);
  for (const key of columns)
    if (!(key in row)) throw new ApiError(400, `Thiếu trường ${key}`);
  text(row.id, "ID");
  if (record.table === "products" || record.table === "product_variants") {
    checkPermission(actor.role, "catalog", actor.issued_role);
    const timestamp = Date.parse(text(row.updated_at, "Thời gian"));
    if (!Number.isFinite(timestamp) || timestamp > Date.now() + 5 * 60000)
      throw new ApiError(
        409,
        "Đồng hồ thiết bị sai. Vui lòng kiểm tra giờ.",
        "CLOCK_SKEW",
      );
    if (
      typeof row.lww_key !== "string" ||
      !row.lww_key.startsWith(`${row.updated_at}|`)
    )
      throw new ApiError(400, "Thiếu phiên bản LWW.");
    if (record.table === "product_variants") {
      money(row.price);
      money(row.cost);
    }
  } else {
    if (
      row.store_id !== actor.store_id ||
      ("device_id" in row && row.device_id !== actor.device_id)
    )
      throw new ApiError(403, "Dữ liệu khác cửa hàng hoặc thiết bị.");
    if (record.table === "stock_threshold_rules") {
      checkPermission(actor.role, "catalog", actor.issued_role);
      if (row.user_id !== actor.user_id)
        throw new ApiError(403, "Sai người cấu hình ngưỡng kho.");
      const stamp = Date.parse(text(row.created_at, "Thời điểm"));
      if (
        !/^[a-f0-9]{8}-[a-f0-9]{4}-7[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(
          String(row.id),
        ) ||
        !Number.isSafeInteger(row.threshold) ||
        Number(row.threshold) < 0 ||
        !Number.isFinite(stamp) ||
        stamp > Date.now() + 300000 ||
        row.version_key !==
          `${new Date(stamp).toISOString()}|${actor.device_id}|${row.id}`
      )
        throw new ApiError(400, "Ngưỡng hoặc phiên bản cảnh báo không hợp lệ.");
      text(row.variant_id, "Biến thể");
    } else if (record.table === "bank_accounts") {
      checkPermission(actor.role, "configure", actor.issued_role);
      if (row.id !== actor.store_id || row.user_id !== actor.user_id)
        throw new ApiError(403, "Sai danh tính cấu hình ngân hàng.");
      const timestamp = Date.parse(text(row.updated_at, "Thời điểm"));
      if (
        !Number.isFinite(timestamp) ||
        timestamp > Date.now() + 300000 ||
        typeof row.lww_key !== "string" ||
        !row.lww_key.startsWith(`${row.updated_at}|`)
      )
        throw new ApiError(400, "Phiên bản cấu hình không hợp lệ.");
      try {
        bankConfig(JSON.parse(text(row.config_json, "Cấu hình", 90000)));
      } catch (error) {
        if (error instanceof ApiError) throw error;
        throw new ApiError(400, "JSON cấu hình không hợp lệ.");
      }
    } else if (record.table === "stock_movements") {
      if (transfers.has(String(row.document_id))) {
        checkPermission(actor.role, "stock", actor.issued_role);
        return;
      }
      if (returns.has(String(row.document_id))) {
        checkPermission(actor.role, "returns", actor.issued_role);
        if (row.user_id !== actor.user_id)
          throw new ApiError(403, "Không được giả danh người đổi/trả.");
        text(row.reason, "Lý do");
        return;
      }
      const isSale = row.kind === "sale" && sales.has(String(row.document_id));
      checkPermission(actor.role, isSale ? "sell" : "stock", actor.issued_role);
      if (!Number.isSafeInteger(row.quantity) || row.quantity === 0)
        throw new ApiError(400, "Số lượng không hợp lệ.");
      if (row.user_id !== actor.user_id)
        throw new ApiError(403, "Không được giả danh người thao tác.");
      text(row.reason, "Lý do");
      if (!isSale && !["receipt", "adjustment"].includes(String(row.kind)))
        throw new ApiError(400, "Loại giao dịch này phải đi cùng chứng từ.");
    } else if (record.table === "attendance_entries") {
      checkPermission(actor.role, "attendance", actor.issued_role);
      if (row.user_id !== actor.user_id)
        throw new ApiError(403, "Không được giả danh người chấm công.");
    } else if (
      record.table === "transfer_events" ||
      record.table === "transfer_receipts"
    ) {
      checkPermission(actor.role, "stock", actor.issued_role);
      if (row.user_id !== actor.user_id)
        throw new ApiError(403, "Không được giả danh người chuyển/nhận kho.");
    } else if (
      [
        "combo_rules",
        "commercial_rules",
        "tailoring_rules",
        "size_rules",
      ].includes(record.table)
    ) {
      checkPermission(actor.role, "catalog", actor.issued_role);
    } else if (
      record.table === "reservation_lines" ||
      record.table === "reservation_events"
    ) {
      checkPermission(
        actor.role,
        record.table === "reservation_events" && row.kind === "release"
          ? "reserve"
          : "sell",
        actor.issued_role,
      );
      if ("user_id" in row && row.user_id !== actor.user_id)
        throw new ApiError(403, "Không được giả danh người giữ hàng.");
    } else if (record.table === "document_events") {
      if (row.type === "CANCELLED")
        checkPermission(actor.role, "voidInvoice", actor.issued_role);
      else if (
        ["TAILOR_SEWING", "TAILOR_READY", "TAILOR_DELIVERED"].includes(
          String(row.type),
        )
      )
        checkPermission(actor.role, "tailoring", actor.issued_role);
      else throw new ApiError(400, "Loại sự kiện không hợp lệ.");
      if (row.user_id !== actor.user_id)
        throw new ApiError(403, "Không được giả danh người cập nhật.");
    } else if (
      ["return_lines", "receivable_adjustments"].includes(record.table)
    ) {
      checkPermission(actor.role, "returns", actor.issued_role);
    } else if (
      ["schools", "school_classes", "students"].includes(record.table)
    ) {
      checkPermission(actor.role, "catalog", actor.issued_role);
      text(row.name, "Tên");
      if (row.active !== 0 && row.active !== 1)
        throw new ApiError(400, "Trạng thái không hợp lệ.");
      const updated = Date.parse(text(row.updated_at, "Thời gian"));
      if (
        !Number.isFinite(updated) ||
        updated > Date.now() + 5 * 60000 ||
        typeof row.lww_key !== "string" ||
        !row.lww_key.startsWith(`${row.updated_at}|`)
      )
        throw new ApiError(400, "Phiên bản danh mục không hợp lệ.");
      if (
        record.table === "schools" &&
        !["Mầm non", "Tiểu học", "THCS", "THPT"].includes(String(row.level))
      )
        throw new ApiError(400, "Cấp học không hợp lệ.");
      if (record.table === "school_classes")
        text(row.academic_year, "Niên khóa");
      if (record.table === "students") text(row.student_code, "Mã học sinh");
    } else if (record.table === "audit_logs") {
      if (row.server_time !== null)
        throw new ApiError(400, "Thời điểm tiếp nhận do server ghi nhận.");
      if (row.user_id !== actor.user_id && row.user_id !== null)
        throw new ApiError(403, "Không được gửi nhật ký của tài khoản khác.");
      if (
        !Number.isSafeInteger(row.chain_index) ||
        (row.chain_index as number) < 1
      )
        throw new ApiError(400, "Chuỗi audit client không hợp lệ.");
    } else {
      checkPermission(
        actor.role,
        transfers.has(
          String(record.table === "documents" ? row.id : row.document_id),
        )
          ? "stock"
          : ["payments", "receivable_entries"].includes(record.table)
            ? "collect"
            : "sell",
        actor.issued_role,
      );
      if ("user_id" in row && row.user_id !== actor.user_id)
        throw new ApiError(403, "Không được giả danh người lập chứng từ.");
      if (record.table === "customers") {
        if (!["parent", "school", "dealer"].includes(String(row.kind)))
          throw new ApiError(400, "Loại khách hàng không hợp lệ.");
        text(row.name, "Tên khách");
        text(row.updated_at, "Thời gian");
        text(row.lww_key, "Phiên bản");
      }
    }
  }
}

export async function push(
  db: D1Database,
  actor: Actor,
  body: Record<string, unknown>,
): Promise<Response> {
  if (
    !Array.isArray(body.mutations) ||
    body.mutations.length < 1 ||
    body.mutations.length > syncLimits.maxRequestMutations
  )
    throw new ApiError(400, "Batch cần 1–5 thay đổi.");
  const acknowledged: string[] = [];
  for (const raw of body.mutations.slice(0, syncLimits.maxProcessedMutations)) {
    if (!raw || typeof raw !== "object")
      throw new ApiError(400, "Thay đổi không hợp lệ.");
    const mutation = raw as Mutation,
      id = text(mutation.id, "ID thay đổi");
    if (
      !Array.isArray(mutation.records) ||
      mutation.records.length < 1 ||
      mutation.records.length > 100
    )
      throw new ApiError(400, "Thay đổi cần 1–100 bản ghi.");
    if (
      mutation.records.some(
        (r) =>
          !r ||
          typeof r !== "object" ||
          typeof r.table !== "string" ||
          !r.row ||
          typeof r.row !== "object" ||
          Array.isArray(r.row),
      )
    )
      throw new ApiError(400, "Bản ghi không hợp lệ.");
    const hash = await sha256(JSON.stringify(mutation.records));
    const previous = await db
      .prepare(
        "SELECT payload_hash FROM processed_mutations WHERE store_id=? AND id=?",
      )
      .bind(actor.store_id, id)
      .first<{ payload_hash: string }>();
    if (previous) {
      if (previous.payload_hash !== hash)
        throw new ApiError(
          409,
          "ID đã dùng với nội dung khác.",
          "IDEMPOTENCY_CONFLICT",
        );
      acknowledged.push(id);
      continue;
    }
    const statements: D1PreparedStatement[] = [];
    if (mutation.records.some((r) => r.table === "attendance_entries")) {
      for (const record of mutation.records)
        validateRecord(record, actor, new Set());
      const rejection = await validateAttendance(db, actor, mutation.records);
      if (rejection) {
        const columns = Object.keys(rejection);
        await db.batch([
          db
            .prepare(
              `INSERT OR IGNORE INTO attendance_rejections (${columns.join(",")}) VALUES (${columns.map(() => "?").join(",")})`,
            )
            .bind(...Object.values(rejection)),
          db
            .prepare(
              "INSERT OR IGNORE INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) VALUES(?,?,?,?,?,?)",
            )
            .bind(
              actor.store_id,
              id,
              "attendance_rejections",
              rejection.id,
              JSON.stringify(rejection),
              new Date().toISOString(),
            ),
          await auditStatement(
            db,
            actor,
            "ATTENDANCE_REJECT",
            String(rejection.employee_id),
            String(rejection.reason),
            { work_day: rejection.work_day, entry_id: rejection.id },
          ),
          db
            .prepare("INSERT INTO processed_mutations VALUES(?,?,?,?,?)")
            .bind(
              actor.store_id,
              id,
              actor.device_id,
              hash,
              new Date().toISOString(),
            ),
        ]);
        acknowledged.push(id);
        continue;
      }
    }
    const returns = await validateReturns(db, actor, mutation.records);
    for (const record of mutation.records.filter(
      (r) => r.table === "size_rules",
    ))
      await validateSizeRule(db, actor, record.row);
    const reservations = await validateReservations(
      db,
      actor,
      mutation.records,
    );
    const transfers = await validateTransfers(db, actor, mutation.records, id);
    const externalDocuments = new Set([
      ...returns,
      ...reservations,
      ...transfers.ids,
    ]);
    await validateTailorEvents(db, actor, mutation.records);
    for (const record of mutation.records.filter(
      (r) => r.table === "tailoring_rules",
    ))
      await validateTailorRule(db, actor, record.row);
    for (const record of mutation.records.filter(
      (r) => r.table === "commercial_rules",
    ))
      await validateCommercialRule(db, actor, record.row);
    if (
      !["owner", "manager"].includes(actor.role) ||
      !["owner", "manager"].includes(actor.issued_role ?? actor.role)
    ) {
      const customerRecords = mutation.records.filter(
        (r) => r.table === "customers",
      );
      const existingCustomers = customerRecords.length
        ? await db.batch(
            customerRecords.map((r) =>
              db
                .prepare("SELECT kind FROM customers WHERE store_id=? AND id=?")
                .bind(actor.store_id, r.row.id),
            ),
          )
        : [];
      let customerIndex = 0;
      for (const record of customerRecords) {
        const existing = existingCustomers[customerIndex++]?.results?.[0] as
          { kind: string } | undefined;
        if (
          (existing && existing.kind !== record.row.kind) ||
          (!existing && record.row.kind !== "parent")
        )
          throw new ApiError(
            403,
            "Không có quyền đổi khách thành trường/đại lý.",
          );
      }
    }
    const collections = await validateCollections(db, actor, mutation.records);
    for (const record of mutation.records.filter(
      (r) => r.table === "combo_rules",
    ))
      await validateComboRule(db, actor, record.row);
    const sales = await validateSales(
      db,
      actor,
      mutation.records,
      collections,
      externalDocuments,
    );
    for (const record of mutation.records)
      validateRecord(record, actor, sales, returns, transfers.ids);
    const immutableRecords = mutation.records.filter(
      (r) => !mutableTables.has(r.table),
    );
    const existingRows = immutableRecords.length
      ? await db.batch(
          immutableRecords.map((r) =>
            db.prepare(`SELECT * FROM ${r.table} WHERE id=?`).bind(r.row.id),
          ),
        )
      : [];
    const existingByKey = new Map(
      immutableRecords.map((r, i) => [
        `${r.table}:${r.row.id}`,
        existingRows[i]?.results?.[0],
      ]),
    );
    for (const documentId of [...sales, ...externalDocuments]) {
      if (existingByKey.get(`documents:${documentId}`)) {
        for (const record of immutableRecords.filter(
          (r) =>
            r.row.document_id === documentId ||
            r.row.credit_document_id === documentId ||
            r.row.related_id === documentId ||
            r.row.related_document_id === documentId ||
            (r.table === "transfer_receipts" && r.row.id === documentId),
        )) {
          if (!existingByKey.get(`${record.table}:${record.row.id}`))
            throw new ApiError(
              409,
              "Không được thêm dòng mới vào hóa đơn đã phát hành.",
              "IMMUTABLE_DOCUMENT",
            );
        }
      }
    }
    const seen = new Set<string>();
    for (const record of mutation.records) {
      validateRecord(record, actor, sales, returns, transfers.ids);
      const recordKey = `${record.table}:${record.row.id}`;
      if (seen.has(recordKey))
        throw new ApiError(400, "Một bundle không được lặp cùng bản ghi.");
      seen.add(recordKey);
      if (record.table === "audit_logs") {
        const row = record.row;
        const archived = await db
          .prepare(
            "SELECT store_id,device_id,record_digest FROM audit_archive_receipts WHERE id=?",
          )
          .bind(row.id)
          .first<{
            store_id: string;
            device_id: string;
            record_digest: string;
          }>();
        if (archived) {
          if (
            archived.store_id !== actor.store_id ||
            archived.device_id !== actor.device_id ||
            archived.record_digest !== (await auditRecordDigest(row))
          )
            throw new ApiError(
              409,
              "Nhật ký đã lưu trữ có nội dung khác.",
              "AUDIT_ARCHIVED_CONFLICT",
            );
          continue;
        }
        let changes: unknown;
        try {
          changes = JSON.parse(String(row.changes_json));
        } catch {
          throw new ApiError(400, "Chi tiết audit không hợp lệ.");
        }
        if (
          !changes ||
          typeof changes !== "object" ||
          Array.isArray(changes) ||
          JSON.stringify(
            redactAuditChanges(
              changes as Record<string, unknown>,
              String(row.action),
            ),
          ) !== JSON.stringify(changes)
        ) {
          throw new ApiError(
            400,
            "Nhật ký chứa dữ liệu bí mật/lương chưa che.",
            "AUDIT_SENSITIVE",
          );
        }
        const canonical = {
          id: row.id,
          store_id: row.store_id,
          device_id: row.device_id,
          user_id: row.user_id,
          role: row.role,
          action: row.action,
          entity_type: row.entity_type,
          entity_id: row.entity_id,
          changes,
          reason: row.reason,
          client_time: row.client_time,
          severity: row.severity,
          hash_prev: row.hash_prev,
          chain_index: row.chain_index,
        };
        if ((await sha256(JSON.stringify(canonical))) !== row.hash)
          throw new ApiError(
            409,
            "Chuỗi băm nhật ký không khớp.",
            "AUDIT_HASH",
          );
        if (row.severity === "critical" && !String(row.reason).trim())
          throw new ApiError(400, "Nhật ký nghiêm trọng cần lý do.");
        const index = row.chain_index as number;
        if (index === 1 && row.hash_prev !== "")
          throw new ApiError(409, "Nhật ký đầu chuỗi không hợp lệ.");
        if (index > 1) {
          const previousRecord = mutation.records.find(
            (r) => r.table === "audit_logs" && r.row.chain_index === index - 1,
          )?.row;
          const previous =
            previousRecord ??
            (await db
              .prepare(
                "SELECT hash FROM audit_logs WHERE store_id=? AND device_id=? AND chain_index=?",
              )
              .bind(actor.store_id, actor.device_id, index - 1)
              .first<{ hash: string }>()) ??
            (await db
              .prepare(
                "SELECT hash FROM audit_chain_checkpoints WHERE store_id=? AND device_id=? AND direction=1 AND chain_index=?",
              )
              .bind(actor.store_id, actor.device_id, index - 1)
              .first<{ hash: string }>());
          if (!previous || previous.hash !== row.hash_prev)
            throw new ApiError(
              409,
              "Thiếu hoặc sai liên kết nhật ký trước.",
              "AUDIT_CHAIN",
            );
        }
      }
      const columns = entityColumns[record.table],
        values = columns.map((key) =>
          record.table === "audit_logs" && key === "server_time"
            ? new Date().toISOString()
            : (record.row[key] as string | number | null),
        );
      const immutable = !mutableTables.has(record.table);
      if (immutable) {
        const existing = existingByKey.get(
          `${record.table}:${record.row.id}`,
        ) as Record<string, unknown> | undefined;
        if (
          existing &&
          columns.some(
            (key) =>
              !(record.table === "audit_logs" && key === "server_time") &&
              existing[key] !== record.row[key],
          )
        )
          throw new ApiError(
            409,
            "Bản ghi bất biến đã tồn tại với nội dung khác.",
          );
      }
      const update = immutable
        ? "DO NOTHING"
        : `DO UPDATE SET ${columns
            .filter((c) => c !== "id")
            .map((c) => `${c}=excluded.${c}`)
            .join(",")} WHERE excluded.lww_key>${record.table}.lww_key`;
      statements.push(
        db
          .prepare(
            `INSERT INTO ${record.table} (${columns.join(",")}) VALUES (${columns.map(() => "?").join(",")}) ON CONFLICT(id) ${update}`,
          )
          .bind(...values),
      );
      if (record.table === "product_variants") {
        // Giữ chứng cứ giá đã bán offline ngay cả khi revision này thua LWW.
        // Trigger từ chối cùng revision có giá khác; batch rollback toàn bộ.
        statements.push(
          db
            .prepare(
              "INSERT OR IGNORE INTO variant_price_history(variant_id,version,price,cost) VALUES(?,?,?,?)",
            )
            .bind(
              record.row.id,
              record.row.lww_key,
              record.row.price,
              record.row.cost,
            ),
        );
      }
      if (record.table === "combo_rules") {
        const r = record.row;
        statements.push(
          db
            .prepare(
              "INSERT OR IGNORE INTO combo_versions VALUES (?,?,?,?,?,?,?,?)",
            )
            .bind(
              r.store_id,
              r.id,
              r.lww_key,
              r.name,
              r.price,
              r.items_json,
              r.active,
              r.updated_at,
            ),
        );
      }
      if (record.table === "commercial_rules") {
        const r = record.row;
        statements.push(
          db
            .prepare(
              "INSERT OR IGNORE INTO commercial_versions VALUES (?,?,?,?,?,?,?,?)",
            )
            .bind(
              r.store_id,
              r.id,
              r.lww_key,
              r.name,
              r.kind,
              r.config_json,
              r.active,
              r.updated_at,
            ),
        );
      }
      if (record.table === "tailoring_rules") {
        const r = record.row;
        statements.push(
          db
            .prepare(
              "INSERT OR IGNORE INTO tailoring_versions VALUES (?,?,?,?,?,?,?)",
            )
            .bind(
              r.store_id,
              r.id,
              r.lww_key,
              r.name,
              r.config_json,
              r.active,
              r.updated_at,
            ),
        );
      }
      const scope = ["products", "product_variants"].includes(record.table)
        ? "*"
        : actor.store_id;
      // Feed luôn chứa giá trị được DB chấp nhận, không phát lại bản LWW đã thua.
      const json = recordJsonExpression(columns);
      statements.push(
        db
          .prepare(
            `INSERT OR IGNORE INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at) SELECT ?,?,?,id,${json},? FROM ${record.table} WHERE id=?`,
          )
          .bind(
            scope,
            id,
            record.table,
            new Date().toISOString(),
            record.row.id,
          ),
      );
    }
    statements.push(...transfers.projections);
    for (const record of mutation.records.filter(
      (r) => r.table === "bank_accounts",
    )) {
      const config = JSON.parse(record.row.config_json as string) as Record<
        string,
        string
      >;
      statements.push(
        await auditStatement(
          db,
          actor,
          "BANK_ACCOUNT_SYNC",
          actor.store_id,
          "Tiếp nhận cấu hình chuyển khoản",
          {
            bank_name: config.bank_name,
            account_last_four: config.account_number.slice(-4),
            has_qr: config.qr_png.length > 0,
          },
        ),
      );
    }
    if (
      actor.device_kind === "web" &&
      mutation.records.some((r) => r.table === "product_variants")
    ) {
      statements.push(
        await auditStatement(
          db,
          actor,
          "PRODUCT_WEB_SAVE",
          String(
            mutation.records.find((r) => r.table === "product_variants")!.row
              .id,
          ),
          text(body.catalog_reason, "Lý do", 200),
          {
            variant_ids: mutation.records
              .filter((r) => r.table === "product_variants")
              .map((r) => r.row.id),
          },
        ),
      );
    }
    statements.push(...(await reportProjection(db, actor, mutation.records)));
    for (const entry of mutation.records.filter(
      (r) => r.table === "attendance_entries",
    )) {
      statements.push(
        await auditStatement(
          db,
          actor,
          "ATTENDANCE_SYNC",
          String(entry.row.employee_id),
          "Tiếp nhận chấm công offline",
          {
            entry_id: entry.row.id,
            work_day: entry.row.work_day,
            day_units: entry.row.day_units,
          },
        ),
      );
    }
    for (const event of mutation.records.filter(
      (r) => r.table === "transfer_events",
    )) {
      statements.push(
        await auditStatement(
          db,
          actor,
          "TRANSFER_DISPATCH_SYNC",
          String(event.row.document_id),
          String(event.row.reason),
        ),
      );
    }
    for (const id of [...sales, ...externalDocuments]) {
      statements.push(
        await auditStatement(
          db,
          actor,
          transfers.ids.has(id)
            ? "TRANSFER_SYNC"
            : reservations.has(id)
              ? "RESERVATION_SYNC"
              : returns.has(id)
                ? "RETURN_SYNC"
                : mutation.records.find(
                      (r) => r.table === "documents" && r.row.id === id,
                    )?.row.type === "MR"
                  ? "TAILOR_SYNC"
                  : "INVOICE_SYNC",
          id,
          "Tiếp nhận hóa đơn offline",
          returns.has(id)
            ? {
                original_id: mutation.records.find(
                  (r) => r.table === "documents" && r.row.id === id,
                )?.row.original_id,
              }
            : {},
          String(
            mutation.records.find(
              (r) => r.table === "documents" && r.row.id === id,
            )!.row.code,
          ),
        ),
      );
    }
    for (const paymentId of collections) {
      const payment = mutation.records.find(
        (r) => r.table === "payments" && r.row.id === paymentId,
      )!;
      statements.push(
        await auditStatement(
          db,
          actor,
          "PAYMENT_SYNC",
          String(payment.row.document_id),
          "Tiếp nhận thu công nợ offline",
          { payment_id: paymentId, amount: payment.row.amount },
        ),
      );
    }
    statements.push(
      db
        .prepare("INSERT INTO processed_mutations VALUES (?,?,?,?,?)")
        .bind(
          actor.store_id,
          id,
          actor.device_id,
          hash,
          new Date().toISOString(),
        ),
    );
    await db.batch(statements);
    acknowledged.push(id);
  }
  return Response.json({ acknowledged });
}

export async function pull(
  db: D1Database,
  actor: Actor,
  url: URL,
): Promise<Response> {
  const auditScope = url.searchParams.get("scope") === "audit";
  const attendanceScope = url.searchParams.get("scope") === "attendance";
  const canAudit =
    ["owner", "manager"].includes(actor.role) &&
    ["owner", "manager"].includes(actor.issued_role ?? actor.role);
  if (auditScope && !canAudit)
    throw new ApiError(403, "Không có quyền xem nhật ký.");
  if (
    attendanceScope &&
    (!rolePermissions[actor.role].includes("attendance") ||
      !rolePermissions[actor.issued_role ?? actor.role].includes("attendance"))
  )
    throw new ApiError(403, "Không có quyền xem chấm công.");
  const scope =
    url.searchParams.get("scope") === "global" ? "*" : actor.store_id;
  const cursor = Number(url.searchParams.get("cursor") ?? "0");
  if (!Number.isSafeInteger(cursor) || cursor < 0)
    throw new ApiError(400, "Con trỏ không hợp lệ.");
  // Cursor audit độc lập với nghiệp vụ, để đổi ca từ thu ngân sang quản lý
  // không bỏ qua log đã được lọc. Mỗi lần vẫn chỉ đọc 100 event qua index.
  const result = await db
    .prepare(
      "SELECT server_seq,entity_type,payload FROM change_feed WHERE store_id=? AND server_seq>? ORDER BY server_seq LIMIT 100",
    )
    .bind(scope, cursor)
    .all<{ server_seq: number; entity_type: string; payload: string }>();
  const events = result.results.filter((e) =>
    attendanceScope
      ? attendanceFeedTypes.includes(e.entity_type)
      : auditScope
        ? e.entity_type === "audit_logs"
        : e.entity_type !== "audit_logs" &&
          !attendanceFeedTypes.includes(e.entity_type),
  );
  return Response.json({
    events,
    cursor: result.results.at(-1)?.server_seq ?? cursor,
    has_more: result.results.length === 100,
  });
}
