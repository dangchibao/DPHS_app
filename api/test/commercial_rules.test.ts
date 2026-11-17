import { it, expect } from "vitest";
import { testDatabase } from "./database";
import { push } from "../src/sync";
import type { Actor } from "../src/auth";

it("Giữ revision giá thua LWW, chặn sửa nội dung cùng revision và chiếm ID chéo cửa hàng", async () => {
  const { db, sqlite } = testDatabase();
  const actor: Actor = {
    user_id: "u1",
    store_id: "s1",
    device_id: "d1",
    role: "owner",
    name: "Chủ",
    session_id: "session",
  };
  const now = new Date().toISOString(),
    old = new Date(Date.now() - 60000).toISOString();
  try {
    sqlite.exec(`INSERT INTO stores VALUES ('s1','NT-CN01','CN01',1,'${now}'),('s2','NT-CN02','CN02',1,'${now}');
      INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES ('d1','s1','A2','Máy','approved','${now}'),('d2','s2','B2','Máy','approved','${now}');
      INSERT INTO users VALUES ('u1','admin','Chủ','hash','salt',1,0,'${now}');`);
    const config = {
      school_id: null,
      customer_kind: null,
      starts_at: null,
      ends_at: null,
      min_total: 0,
      min_quantity: 1,
      allow_combo: false,
      allow_price_list: false,
      prices: {},
      discount_type: "fixed",
      value: 1000,
      voucher: "",
    };
    const newer = {
      id: "r1",
      store_id: "s1",
      name: "Mới",
      kind: "promotion",
      config_json: JSON.stringify(config),
      active: 1,
      updated_at: now,
      lww_key: `${now}|d1|new`,
    };
    await push(db, actor, {
      mutations: [
        { id: "new", records: [{ table: "commercial_rules", row: newer }] },
      ],
    });
    const older = {
      ...newer,
      name: "Cũ",
      config_json: JSON.stringify({ ...config, value: 2000 }),
      updated_at: old,
      lww_key: `${old}|d1|old`,
    };
    await push(db, actor, {
      mutations: [
        { id: "old", records: [{ table: "commercial_rules", row: older }] },
      ],
    });
    expect(
      sqlite.prepare("SELECT name FROM commercial_rules").get()?.name,
    ).toBe("Mới");
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM commercial_versions").get()?.n,
    ).toBe(2);
    await expect(
      push(db, actor, {
        mutations: [
          {
            id: "change-version",
            records: [
              {
                table: "commercial_rules",
                row: { ...newer, config_json: older.config_json },
              },
            ],
          },
        ],
      }),
    ).rejects.toThrow("COMMERCIAL_VERSION_CONFLICT");
    await expect(
      push(
        db,
        { ...actor, store_id: "s2", device_id: "d2" },
        {
          mutations: [
            {
              id: "steal",
              records: [
                {
                  table: "commercial_rules",
                  row: { ...newer, store_id: "s2" },
                },
              ],
            },
          ],
        },
      ),
    ).rejects.toThrow("STORE_ID_CONFLICT");
    sqlite.exec(
      `INSERT INTO customers VALUES('dealer','s1','Đại lý','','dealer','${now}','${now}|d1|customer');`,
    );
    await expect(
      push(
        db,
        { ...actor, role: "cashier" },
        {
          mutations: [
            {
              id: "lower-kind",
              records: [
                {
                  table: "customers",
                  row: {
                    id: "dealer",
                    store_id: "s1",
                    name: "Sai",
                    phone: "",
                    kind: "parent",
                    updated_at: now,
                    lww_key: `${now}|d1|x`,
                  },
                },
              ],
            },
          ],
        },
      ),
    ).rejects.toThrow("quyền");
  } finally {
    sqlite.close();
  }
});
