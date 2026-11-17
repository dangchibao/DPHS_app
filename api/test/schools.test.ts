import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { push, type SyncRecord } from "../src/sync";
import type { Actor } from "../src/auth";

it("Danh mục trường đồng bộ LWW; chặn sửa bởi thu ngân và tham chiếu chéo cửa hàng", async () => {
  const { db, sqlite } = testDatabase(),
    now = new Date().toISOString();
  const actor: Actor = {
    user_id: "u1",
    store_id: "s1",
    device_id: "d1",
    role: "owner",
    name: "Chủ",
    session_id: "session",
  };
  sqlite.exec(`INSERT INTO stores VALUES ('s1','NT-CN01','CN01',1,'${now}'),('s2','NT-CN02','CN02',1,'${now}');
    INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES('d1','s1','A2','Máy','approved','${now}');
    INSERT INTO users VALUES('u1','admin','Chủ','hash','salt',1,0,'${now}');`);
  const customer: SyncRecord = {
    table: "customers",
    row: {
      id: "customer-school",
      store_id: "s1",
      name: "Trường",
      phone: "",
      kind: "school",
      updated_at: now,
      lww_key: `${now}|d1|customer`,
    },
  };
  const school: SyncRecord = {
    table: "schools",
    row: {
      id: "school1",
      store_id: "s1",
      name: "TH Ngọc Thanh",
      level: "Tiểu học",
      customer_id: "customer-school",
      active: 1,
      updated_at: now,
      lww_key: `${now}|d1|school`,
    },
  };
  const cl: SyncRecord = {
    table: "school_classes",
    row: {
      id: "class1",
      store_id: "s1",
      school_id: "school1",
      name: "2A",
      academic_year: "2026–2027",
      active: 1,
      updated_at: now,
      lww_key: `${now}|d1|class`,
    },
  };
  try {
    sqlite
      .prepare("INSERT INTO customers VALUES (?,?,?,?,?,?,?)")
      .run(
        "foreign-customer",
        "s2",
        "Khách cửa hàng khác",
        "",
        "parent",
        now,
        `${now}|d2|foreign`,
      );
    await expect(
      push(db, actor, {
        mutations: [
          {
            id: "take-over",
            records: [
              { ...customer, row: { ...customer.row, id: "foreign-customer" } },
            ],
          },
        ],
      }),
    ).rejects.toThrow("STORE_ID_CONFLICT");
    expect(
      sqlite
        .prepare(
          "SELECT store_id,name FROM customers WHERE id='foreign-customer'",
        )
        .get(),
    ).toMatchObject({ store_id: "s2", name: "Khách cửa hàng khác" });
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM change_feed").get()?.n,
    ).toBe(0);
    await push(db, actor, {
      mutations: [{ id: "school-job", records: [customer, school, cl] }],
    });
    await push(db, actor, {
      mutations: [{ id: "school-job", records: [customer, school, cl] }],
    });
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM school_classes").get()?.n,
    ).toBe(1);
    await expect(
      push(
        db,
        { ...actor, role: "cashier" },
        {
          mutations: [
            {
              id: "forbidden",
              records: [
                { ...school, row: { ...school.row, name: "Không được sửa" } },
              ],
            },
          ],
        },
      ),
    ).rejects.toThrow("quyền");
    const foreign = {
      ...cl,
      row: { ...cl.row, id: "class-other", store_id: "s2" },
    };
    await expect(
      push(db, actor, { mutations: [{ id: "foreign", records: [foreign] }] }),
    ).rejects.toThrow("cửa hàng");
    const foreignActor = { ...actor, store_id: "s2" };
    await expect(
      push(db, foreignActor, {
        mutations: [{ id: "foreign-parent", records: [foreign] }],
      }),
    ).rejects.toThrow("FOREIGN KEY");
    expect(
      sqlite
        .prepare("SELECT id FROM school_classes WHERE id='class-other'")
        .get(),
    ).toBeUndefined();
    const oldTime = new Date(Date.now() - 60000).toISOString();
    await push(db, actor, {
      mutations: [
        {
          id: "old",
          records: [
            {
              ...school,
              row: {
                ...school.row,
                name: "Tên cũ",
                updated_at: oldTime,
                lww_key: `${oldTime}|d1|old`,
              },
            },
          ],
        },
      ],
    });
    expect(sqlite.prepare("SELECT name FROM schools").get()?.name).toBe(
      "TH Ngọc Thanh",
    );
  } finally {
    sqlite.close();
  }
});
