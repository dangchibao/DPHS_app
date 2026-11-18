import { auditStatement } from "./audit";
import { minimumSyncSchema } from "./config";
import { credential, passwordHash, text } from "./security";

export interface OwnerProvision {
  userId: string;
  storeId: string;
  deviceId: string;
  assignmentId: string;
  username: string;
  storeCode: string;
  storeName: string;
  salt: string;
  credential: string;
}

/** Admin CLI only, deliberately never routed by the public Worker. */
export async function provisionOwner(db: D1Database, input: OwnerProvision) {
  for (const value of [
    input.userId,
    input.storeId,
    input.deviceId,
    input.assignmentId,
  ])
    if (!/^[a-zA-Z0-9_-]{1,100}$/.test(value)) throw new Error("PROVISION_ID");
  const username = text(input.username, "Tài khoản", 80);
  const storeCode = text(input.storeCode, "Mã cửa hàng", 30);
  const storeName = text(input.storeName, "Tên cửa hàng", 120);
  if (!/^NT-[A-Z0-9]{2,12}$/.test(storeCode))
    throw new Error("PROVISION_STORE_CODE");
  const salt = credential(input.salt);
  const verifier = await passwordHash(credential(input.credential), salt);
  const metadata = await db
    .prepare("SELECT version FROM schema_metadata ORDER BY version")
    .all<{ version: number }>();
  if (
    metadata.results.length !== minimumSyncSchema ||
    metadata.results.some((r, i) => r.version !== i + 1)
  )
    throw new Error("PROVISION_SCHEMA");
  const tables = (
    await db
      .prepare("SELECT name FROM sqlite_master WHERE type='table'")
      .all<{ name: string }>()
  ).results
    .map((r) => r.name)
    .filter(
      (name) =>
        !name.startsWith("sqlite_") &&
        !name.startsWith("_cf_") &&
        !["d1_migrations", "schema_metadata"].includes(name),
    );
  if (
    tables.some((name) => !/^[a-z_]+$/.test(name)) ||
    !tables.includes("local_settings")
  )
    throw new Error("PROVISION_TABLES");
  const empty = tables
    .map((name) => `NOT EXISTS(SELECT 1 FROM "${name}" LIMIT 1)`)
    .join(" AND ");
  if (
    !(await db.prepare(`SELECT (${empty}) AS empty`).first<{ empty: number }>())
      ?.empty
  )
    throw new Error("PROVISION_NOT_EMPTY");
  const now = new Date().toISOString();
  const receipt = JSON.stringify({
    user_id: input.userId,
    store_id: input.storeId,
    device_id: input.deviceId,
    schema: minimumSyncSchema,
  });
  await db.batch([
    // NOT NULL + the unique marker also protect the read/batch race. No public
    // bootstrap mode, and no partial owner/store if any statement fails.
    db
      .prepare(
        `INSERT INTO local_settings(key,value) VALUES ('cloud_provision_owner',CASE WHEN ${empty} THEN ? ELSE NULL END)`,
      )
      .bind(receipt),
    db
      .prepare("INSERT INTO stores VALUES (?,?,?,?,?)")
      .bind(input.storeId, storeCode, storeName, 1, now),
    db
      .prepare(
        "INSERT INTO devices(id,store_id,code,name,status,created_at,kind) VALUES (?,?,?,?,?,?,?)",
      )
      .bind(
        input.deviceId,
        input.storeId,
        "W1",
        "Trình duyệt chủ hệ thống",
        "approved",
        now,
        "web",
      ),
    db
      .prepare("INSERT INTO users VALUES (?,?,?,?,?,?,?,?)")
      .bind(input.userId, username, "Chủ hệ thống", verifier, salt, 1, 0, now),
    db
      .prepare("INSERT INTO employee_store_assignments VALUES (?,?,?,?,?,?)")
      .bind(input.assignmentId, input.storeId, input.userId, "owner", 1, now),
    await auditStatement(
      db,
      {
        user_id: input.userId,
        store_id: input.storeId,
        device_id: input.deviceId,
        role: "owner",
      },
      "SYSTEM_BOOTSTRAP",
      input.userId,
      "Khởi tạo cloud bằng CLI kiểm soát trên database trống",
      { store_code: storeCode, device_kind: "web" },
    ),
  ]);
  return {
    user_id: input.userId,
    store_id: input.storeId,
    device_id: input.deviceId,
    username,
  };
}
