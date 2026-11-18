import { it, expect } from "vitest";
import { writeFileSync } from "node:fs";
import { testDatabase } from "../test/database";
import { push } from "../src/sync";
import { sha256 } from "../src/security";
import type { Actor } from "../src/auth";
import type { SyncRecord } from "../src/sync";
import { cloudBudget } from "../src/config";

it("Mô phỏng 3 cửa hàng, 10 thiết bị, 900 hóa đơn/ngày", async () => {
  const { db, sqlite } = testDatabase();
  const now = new Date().toISOString(),
    day = new Date(Date.now() + 7 * 3600000)
      .toISOString()
      .slice(0, 10)
      .replaceAll("-", "");
  const actors: Actor[] = [],
    chains = new Map<string, { index: number; hash: string }>();
  try {
    sqlite
      .prepare("INSERT INTO users VALUES (?,?,?,?,?,?,?,?)")
      .run("owner", "admin", "Chủ", "hash", "salt", 1, 0, now);
    for (let s = 1; s <= 3; s++) {
      sqlite
        .prepare("INSERT INTO stores VALUES (?,?,?,?,?)")
        .run(`s${s}`, `NT-CN0${s}`, `CN0${s}`, 1, now);
      for (let d = 1; d <= (s === 1 ? 4 : 3); d++) {
        const device = `s${s}d${d}`;
        sqlite
          .prepare(
            "INSERT INTO devices(id,store_id,code,name,status,created_at) VALUES (?,?,?,?,?,?)",
          )
          .run(device, `s${s}`, `A${s}${d}`, device, "approved", now);
        actors.push({
          user_id: "owner",
          store_id: `s${s}`,
          device_id: device,
          role: "owner",
          name: "Chủ",
          session_id: "load",
        });
        chains.set(device, { index: 0, hash: "" });
      }
    }
    for (let v = 1; v <= 4; v++) {
      sqlite
        .prepare(
          "INSERT INTO products(id,name,category,gender,school_level,school_year,updated_at) VALUES (?,?,?,?,?,?,?)",
        )
        .run(
          `p${v}`,
          `Sản phẩm ${v}`,
          "Áo sơ mi",
          "Unisex",
          "Tiểu học",
          "2026–2027",
          now,
        );
      sqlite
        .prepare(
          "INSERT INTO product_variants(id,product_id,sku,size,color,unit,cost,price,updated_at,lww_key) VALUES (?,?,?,?,?,?,?,?,?,?)",
        )
        .run(
          `v${v}`,
          `p${v}`,
          `SKU${v}`,
          "M",
          "Trắng",
          "cái",
          50000,
          100000,
          now,
          "version1",
        );
      for (const actor of actors)
        sqlite
          .prepare("INSERT INTO stock_movements VALUES (?,?,?,?,?,?,?,?,?,?)")
          .run(
            `initial-${actor.device_id}-${v}`,
            actor.store_id,
            actor.device_id,
            `v${v}`,
            1000,
            "receipt",
            null,
            "Tồn đầu",
            "owner",
            now,
          );
    }
    const tables = (
      sqlite
        .prepare(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .all() as { name: string }[]
    ).map((r) => r.name);
    const counts = () => {
      const result = new Map<string, number>();
      for (const table of tables) {
        const indexes = sqlite
          .prepare(`PRAGMA index_list('${table}')`)
          .all() as { name: string }[];
        for (const index of indexes) {
          const definition = sqlite
            .prepare(
              "SELECT sql FROM sqlite_master WHERE type='index' AND name=?",
            )
            .get(index.name)?.sql;
          const predicate =
            typeof definition === "string"
              ? definition.match(/\bWHERE\s+([\s\S]+)$/i)?.[1]
              : undefined;
          // Schema nội bộ, không phải SQL do người dùng nhập. Partial index chỉ
          // tính các dòng thật sự có entry, không nhân cả bảng cho index rỗng.
          const count = Number(
            sqlite
              .prepare(
                `SELECT COUNT(*) AS n FROM "${table.replaceAll('"', '""')}" ${predicate ? `WHERE ${predicate}` : ""}`,
              )
              .get()!.n,
          );
          result.set(index.name, count);
        }
      }
      return result;
    };
    const before = counts(),
      changesBefore = Number(
        sqlite.prepare("SELECT total_changes() AS n").get()!.n,
      );
    let pushes = 0,
      partial = 0;
    for (let s = 1; s <= 3; s++) {
      const devices = actors.filter((a) => a.store_id === `s${s}`);
      for (let i = 1; i <= 300; i++) {
        const actor = devices[(i - 1) % devices.length],
          id = `invoice-${s}-${i}`,
          customer = i % 5 === 0 ? `customer-${s}-${i}` : null;
        const code = `HD-CN0${s}-A${s}${((i - 1) % devices.length) + 1}-${day}-${String(i).padStart(3, "0")}`;
        const paid = customer ? 100000 : 400000;
        if (customer) partial++;
        const records: SyncRecord[] = [];
        if (customer)
          records.push({
            table: "customers",
            row: {
              id: customer,
              store_id: actor.store_id,
              name: "Phụ huynh mô phỏng",
              phone: "",
              kind: "parent",
              updated_at: now,
              lww_key: `${now}|${actor.device_id}|${id}`,
            },
          });
        records.push({
          table: "documents",
          row: {
            id,
            store_id: actor.store_id,
            device_id: actor.device_id,
            type: "HD",
            kind: "sale",
            code,
            issued_at: now,
            user_id: "owner",
            customer_id: customer,
            original_id: null,
            subtotal: 400000,
            discount: 0,
            total: 400000,
            school_year: "2026–2027",
            metadata_json: JSON.stringify({
              customer_name: customer ? "Phụ huynh mô phỏng" : "",
              paid,
              change: 0,
            }),
          },
        });
        for (let v = 1; v <= 4; v++)
          records.push({
            table: "invoice_lines",
            row: {
              id: `${id}-line-${v}`,
              store_id: actor.store_id,
              document_id: id,
              variant_id: `v${v}`,
              name: `Sản phẩm ${v}`,
              size: "M",
              color: "Trắng",
              unit: "cái",
              quantity: 1,
              unit_price: 100000,
              unit_cost: 50000,
              discount: 0,
              price_version: "version1",
            },
          });
        records.push({
          table: "payments",
          row: {
            id: `${id}-payment`,
            store_id: actor.store_id,
            device_id: actor.device_id,
            document_id: id,
            user_id: "owner",
            amount: paid,
            method: "cash",
            direction: "receive",
            created_at: now,
            note: "Mô phỏng",
          },
        });
        if (customer)
          records.push({
            table: "receivable_entries",
            row: {
              id: `${id}-debt`,
              store_id: actor.store_id,
              customer_id: customer,
              document_id: id,
              payment_id: null,
              amount: 300000,
              due_date: now.slice(0, 10),
              created_at: now,
            },
          });
        for (let v = 1; v <= 4; v++)
          records.push({
            table: "stock_movements",
            row: {
              id: `${id}-move-${v}`,
              store_id: actor.store_id,
              device_id: actor.device_id,
              variant_id: `v${v}`,
              quantity: -1,
              kind: "sale",
              document_id: id,
              reason: `Bán ${code}`,
              user_id: "owner",
              created_at: now,
            },
          });
        const mutations = [{ id: `${id}-mutation`, records }];
        for (const action of ["INVOICE_CREATE", "PAYMENT_RECEIVE"]) {
          const chain = chains.get(actor.device_id)!;
          chain.index++;
          const logId = `${id}-${action}`,
            changes = { code, total: 400000, paid };
          const payload = {
            id: logId,
            store_id: actor.store_id,
            device_id: actor.device_id,
            user_id: "owner",
            role: "owner",
            action,
            entity_type: "document",
            entity_id: id,
            changes,
            reason: "",
            client_time: now,
            severity: "normal",
            hash_prev: chain.hash,
            chain_index: chain.index,
          };
          const hash = await sha256(JSON.stringify(payload));
          const row = {
            id: logId,
            store_id: actor.store_id,
            device_id: actor.device_id,
            user_id: "owner",
            role: "owner",
            action,
            entity_type: "document",
            entity_id: id,
            document_code: null,
            changes_json: JSON.stringify(changes),
            reason: "",
            client_time: now,
            server_time: null,
            app_version: "0.1.0",
            severity: "normal",
            hash_prev: chain.hash,
            hash,
            chain_index: chain.index,
          };
          chain.hash = hash;
          mutations.push({
            id: `${logId}-mutation`,
            records: [{ table: "audit_logs", row }],
          });
        }
        await push(db, actor, { mutations });
        pushes++;
      }
    }
    const after = counts(),
      baseWrites =
        Number(sqlite.prepare("SELECT total_changes() AS n").get()!.n) -
        changesBefore;
    const indexWrites = [...after].reduce(
      (sum, [index, count]) =>
        sum + Math.max(0, count - (before.get(index) ?? 0)),
      0,
    );
    const writes = baseWrites + indexWrites;
    const polls = 10 * 12 * 60,
      requests = polls * 4 + pushes * 4 + 100;
    const feedRows = Number(
      sqlite.prepare("SELECT COUNT(*) AS n FROM change_feed").get()!.n,
    );
    // Bổ sung ngân sách lookup/JSON-cache, chưa thay cho D1 meta thực tế.
    const reads = polls * 8 + requests * 5 + 900 * 140 + feedRows * 6;
    const pageSize = Number(
        sqlite.prepare("PRAGMA page_size").get()!.page_size,
      ),
      pageCount = Number(sqlite.prepare("PRAGMA page_count").get()!.page_count),
      bytes = pageSize * pageCount;
    expect(sqlite.prepare("SELECT COUNT(*) AS n FROM documents").get()!.n).toBe(
      900,
    );
    expect(
      sqlite
        .prepare(
          "SELECT SUM(amount) AS total FROM payments WHERE direction='receive'",
        )
        .get()!.total,
    ).toBe(306000000);
    expect(
      sqlite.prepare("SELECT COUNT(*) AS n FROM report_receipts").get()!.n,
    ).toBe(900);
    expect(
      sqlite
        .prepare(
          "SELECT SUM(CAST(json_extract(metrics_json,'$.revenue') AS INTEGER)) AS n FROM daily_reports",
        )
        .get()!.n,
    ).toBe(360000000);
    expect(
      sqlite.prepare("SELECT MAX(overflow) AS n FROM daily_reports").get()!.n,
    ).toBe(0);
    const report = `# Mô phỏng tải — schema ${Number(sqlite.prepare("SELECT MAX(version) n FROM schema_metadata").get()!.n)} / 3 cửa hàng / 10 thiết bị\n\nĐã chạy ${now}. Mô phỏng SQLite dùng cùng migration và hàm push của Workers; không phải benchmark CPU cloud.\n\n900 hóa đơn/ngày (300/cửa hàng), 4 dòng/hóa đơn, 1 thanh toán, ${partial} đơn đặt cọc, 2 audit client và 1 audit API/hóa đơn. Kiểm tra tổng thu: 306.000.000đ.\n\n|Chỉ số|Kết quả / ước tính|Free|\n|---|---:|---:|\n|Requests (12 giờ, pull 60 giây, directory + 3 scope, tính bảo thủ mọi máy có quyền audit)|${requests}|${cloudBudget.workersRequestsPerDay}|\n|Rows read (ngân sách bảo thủ, cần đối chiếu D1 meta)|${reads}|${cloudBudget.d1RowsReadPerDay}|\n|Rows written cơ sở SQLite, gồm trigger|${baseWrites}|—|\n|Ghi index ước tính theo schema|${indexWrites}|—|\n|Tổng rows written ước tính|${writes}|${cloudBudget.d1RowsWrittenPerDay}|\n|Dung lượng SQLite của dữ liệu mô phỏng|${bytes} bytes|${cloudBudget.d1DatabaseBytes} bytes/database|\n\n${writes <= cloudBudget.d1RowsWrittenPerDay ? (writes > cloudBudget.d1RowsWrittenPerDay * 0.9 ? "Kịch bản sát hạn mức ghi; không đủ phần dư an toàn cho nghiệp vụ thường ngày và backup." : "Kịch bản cơ sở nằm trong ngân sách ghi ước tính.") : "Kịch bản vượt ngân sách ghi; không được tuyên bố đạt 0đ/tháng ở tải này."} Đã gồm tổng hợp tài chính, receipt chống đếm trùng và cache công nợ ban đầu. Còn phải tính các lượt đọc báo cáo, thu nợ tiếp, may/đổi trả/giữ/chuyển kho, chấm công/lương, nhật ký đọc/đăng nhập, quản trị, retry, bookkeeping D1 và dịch vụ dùng chung account. Không chứng minh CPU 10ms bằng thời gian test SQLite; cần profiling Workers trước production.\n\nBản tính index dùng tăng số entry từng index, có lọc predicate của partial index; chưa phải số đo billing D1. Cần đo meta.rows_written/rows_read và analytics trên môi trường cloud do chủ cấp phép. Kịch bản 8 dòng/hóa đơn, nhiều audit/đổi trả hoặc nghiệp vụ bổ sung có thể vượt Free; không coi phần dư của kịch bản này là ngân sách vận hành an toàn.\n\nFeed nghiệp vụ vẫn giữ toàn bộ để không mất dữ liệu máy offline; schema 30 có compaction audit riêng sau file private verified, phần đó chưa được chạy trong mô phỏng này. Không cam kết dung lượng miễn phí lâu dài: phải đo tăng trưởng và hoàn thiện snapshot/cursor expiry/lưu trữ trước khi bật retention. D1 export cần đo riêng ngoài giờ; không tính là 0 reads khi chưa có bằng chứng.\n\nNguồn hạn mức: ${cloudBudget.sources.join(" ; ")}\n`;
    writeFileSync("../docs/phases/load-simulation.md", report, "utf8");
    console.log(
      JSON.stringify({
        invoices: 900,
        pushes,
        requests,
        baseWrites,
        indexWrites,
        estimatedWrites: writes,
        bytes,
      }),
    );
  } finally {
    sqlite.close();
  }
});
