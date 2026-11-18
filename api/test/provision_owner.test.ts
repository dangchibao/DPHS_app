import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { testDatabase } from "./database";
import { provisionOwner, type OwnerProvision } from "../src/provision_owner";
import { passwordHash } from "../src/security";

describe("Khởi tạo owner cloud chỉ trên DB trống", () => {
  let database: ReturnType<typeof testDatabase>;
  const input: OwnerProvision = {
    userId: "owner1",
    storeId: "store1",
    deviceId: "web1",
    assignmentId: "assign1",
    username: "admin",
    storeCode: "NT-CN01",
    storeName: "Ngọc Thanh",
    salt: "a".repeat(64),
    credential: "b".repeat(64),
  };
  beforeEach(() => {
    database = testDatabase();
  });
  afterEach(() => database.sqlite.close());
  it("Cùng transaction tạo chủ, quyền, Web approved và audit, chỉ lưu verifier", async () => {
    const result = await provisionOwner(database.db, input);
    expect(result).toMatchObject({ username: "admin", store_id: "store1" });
    expect(
      database.sqlite
        .prepare("SELECT password_hash,must_change_password FROM users")
        .get(),
    ).toEqual({
      password_hash: await passwordHash(input.credential, input.salt),
      must_change_password: 0,
    });
    expect(
      database.sqlite
        .prepare("SELECT kind,status,installation_hash FROM devices")
        .get(),
    ).toEqual({ kind: "web", status: "approved", installation_hash: null });
    expect(
      database.sqlite
        .prepare("SELECT role FROM employee_store_assignments")
        .get()?.role,
    ).toBe("owner");
    expect(
      database.sqlite
        .prepare("SELECT action,chain_index,hash_prev FROM audit_logs")
        .get(),
    ).toEqual({ action: "SYSTEM_BOOTSTRAP", chain_index: -1, hash_prev: "" });
    await expect(provisionOwner(database.db, input)).rejects.toThrow(
      "PROVISION_NOT_EMPTY",
    );
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM users").get()?.n,
    ).toBe(1);
  });
  it("Từ chối dữ liệu đã có, kể cả danh mục chưa có user", async () => {
    database.sqlite.exec(
      "INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES ('p1','Áo','Áo','Unisex','Tiểu học','2026','2026-11-17')",
    );
    await expect(provisionOwner(database.db, input)).rejects.toThrow(
      "PROVISION_NOT_EMPTY",
    );
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM users").get()?.n,
    ).toBe(0);
  });
  it("Dữ liệu tới sau preflight làm guard hủy transaction", async () => {
    const batch = database.db.batch.bind(database.db);
    database.db.batch = (async (statements: D1PreparedStatement[]) => {
      database.sqlite.exec(
        "INSERT INTO local_settings VALUES ('fixture-race','keep')",
      );
      return batch(statements);
    }) as typeof database.db.batch;
    await expect(provisionOwner(database.db, input)).rejects.toThrow();
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM users").get()?.n,
    ).toBe(0);
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM stores").get()?.n,
    ).toBe(0);
    expect(
      database.sqlite
        .prepare("SELECT value FROM local_settings WHERE key='fixture-race'")
        .get()?.value,
    ).toBe("keep");
  });
  it("Lỗi cuối batch hoàn tác cả marker, chủ và cửa hàng", async () => {
    database.sqlite.exec(
      "CREATE TRIGGER fixture_deny BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT,'fixture'); END",
    );
    await expect(provisionOwner(database.db, input)).rejects.toThrow("fixture");
    for (const table of [
      "stores",
      "users",
      "devices",
      "employee_store_assignments",
      "local_settings",
    ])
      expect(
        database.sqlite.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()?.n,
      ).toBe(0);
  });
  it("Schema thiếu hoặc định danh sai đều không ghi dữ liệu", async () => {
    await expect(
      provisionOwner(database.db, { ...input, storeId: "bad'id" }),
    ).rejects.toThrow("PROVISION_ID");
    database.sqlite.exec("DELETE FROM schema_metadata WHERE version=30");
    await expect(provisionOwner(database.db, input)).rejects.toThrow(
      "PROVISION_SCHEMA",
    );
    expect(
      database.sqlite.prepare("SELECT COUNT(*) AS n FROM users").get()?.n,
    ).toBe(0);
  });
});
