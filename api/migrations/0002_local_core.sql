-- @statement
CREATE TABLE users (
 id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
 password_hash TEXT NOT NULL, salt TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
 must_change_password INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL
);
-- @statement
CREATE TABLE employee_store_assignments (
 id TEXT PRIMARY KEY, store_id TEXT NOT NULL REFERENCES stores(id), user_id TEXT NOT NULL REFERENCES users(id),
 role TEXT NOT NULL CHECK(role IN ('owner','manager','cashier','warehouse','accountant')),
 active INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL, UNIQUE(store_id,user_id)
);
-- @statement
CREATE INDEX assignments_store_user ON employee_store_assignments(store_id,user_id,active);
-- @statement
CREATE TABLE products (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, gender TEXT NOT NULL,
 school_level TEXT NOT NULL, school_year TEXT NOT NULL, image_path TEXT,
 active INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1
);
-- @statement
CREATE TABLE product_variants (
 id TEXT PRIMARY KEY, product_id TEXT NOT NULL REFERENCES products(id), sku TEXT NOT NULL UNIQUE,
 barcode TEXT UNIQUE, size TEXT NOT NULL, color TEXT NOT NULL, unit TEXT NOT NULL,
 cost INTEGER NOT NULL CHECK(cost>=0), price INTEGER NOT NULL CHECK(price>=0),
 active INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,
 UNIQUE(product_id,size,color,unit)
);
-- @statement
CREATE TABLE store_variant_settings (
 store_id TEXT NOT NULL REFERENCES stores(id), variant_id TEXT NOT NULL REFERENCES product_variants(id),
 price_override INTEGER CHECK(price_override>=0), low_stock_threshold INTEGER NOT NULL DEFAULT 5 CHECK(low_stock_threshold>=0),
 PRIMARY KEY(store_id,variant_id)
);
-- @statement
CREATE TABLE stock_movements (
 id TEXT PRIMARY KEY, store_id TEXT NOT NULL REFERENCES stores(id), device_id TEXT NOT NULL REFERENCES devices(id),
 variant_id TEXT NOT NULL REFERENCES product_variants(id), quantity INTEGER NOT NULL CHECK(quantity<>0),
 kind TEXT NOT NULL CHECK(kind IN ('receipt','sale','return','adjustment','transfer_out','transfer_in','reversal')),
 document_id TEXT, reason TEXT NOT NULL CHECK(length(trim(reason))>0), user_id TEXT NOT NULL REFERENCES users(id),
 created_at TEXT NOT NULL, UNIQUE(store_id,id)
);
-- @statement
CREATE INDEX movements_store_variant_time ON stock_movements(store_id,variant_id,created_at);
-- @statement
CREATE TABLE stock_balances (
 store_id TEXT NOT NULL REFERENCES stores(id), variant_id TEXT NOT NULL REFERENCES product_variants(id),
 quantity INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(store_id,variant_id)
);
-- @statement
CREATE TRIGGER stock_insert AFTER INSERT ON stock_movements BEGIN
 INSERT INTO stock_balances(store_id,variant_id,quantity) VALUES(NEW.store_id,NEW.variant_id,NEW.quantity)
 ON CONFLICT(store_id,variant_id) DO UPDATE SET quantity=quantity+NEW.quantity;
END;
-- @statement
CREATE TRIGGER stock_no_update BEFORE UPDATE ON stock_movements BEGIN SELECT RAISE(ABORT,'stock_movements append-only'); END;
-- @statement
CREATE TRIGGER stock_no_delete BEFORE DELETE ON stock_movements BEGIN SELECT RAISE(ABORT,'stock_movements append-only'); END;
-- @statement
CREATE TABLE audit_logs (
 id TEXT PRIMARY KEY, store_id TEXT NOT NULL REFERENCES stores(id), device_id TEXT NOT NULL REFERENCES devices(id),
 user_id TEXT, role TEXT NOT NULL, action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
 document_code TEXT, changes_json TEXT NOT NULL, reason TEXT NOT NULL,
 client_time TEXT NOT NULL, server_time TEXT, app_version TEXT NOT NULL,
 severity TEXT NOT NULL CHECK(severity IN ('normal','sensitive','critical')),
 hash_prev TEXT NOT NULL, hash TEXT NOT NULL, chain_index INTEGER NOT NULL,
 UNIQUE(store_id,device_id,chain_index)
);
-- @statement
CREATE INDEX audit_store_time ON audit_logs(store_id,client_time);
-- @statement
CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_logs BEGIN SELECT RAISE(ABORT,'audit_logs append-only'); END;
-- @statement
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_logs BEGIN SELECT RAISE(ABORT,'audit_logs append-only'); END;
-- @statement
CREATE TABLE local_settings (key TEXT PRIMARY KEY,value TEXT NOT NULL);
-- @statement
CREATE TABLE outbox (
 id TEXT PRIMARY KEY, store_id TEXT NOT NULL, device_id TEXT NOT NULL,
 entity_type TEXT NOT NULL, payload TEXT NOT NULL, priority INTEGER NOT NULL,
 created_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT
);
-- @statement
CREATE INDEX outbox_store_priority ON outbox(store_id,priority,created_at);
-- @statement
CREATE TABLE sync_cursors (store_id TEXT PRIMARY KEY,server_seq INTEGER NOT NULL DEFAULT 0);
-- @statement
CREATE TABLE document_counters (
 store_id TEXT NOT NULL,device_id TEXT NOT NULL,type TEXT NOT NULL,day TEXT NOT NULL,
 value INTEGER NOT NULL CHECK(value>0), PRIMARY KEY(store_id,device_id,type,day)
);
-- @statement
CREATE TABLE device_stock_allocations (
 store_id TEXT NOT NULL,device_id TEXT NOT NULL,variant_id TEXT NOT NULL,
 quantity INTEGER NOT NULL CHECK(quantity>=0), PRIMARY KEY(store_id,device_id,variant_id),
 FOREIGN KEY(store_id,device_id) REFERENCES devices(store_id,id),
 FOREIGN KEY(variant_id) REFERENCES product_variants(id)
);
-- @statement
INSERT INTO schema_metadata VALUES (2,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
