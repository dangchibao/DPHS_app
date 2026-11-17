-- @statement
CREATE TABLE customers (
 id TEXT PRIMARY KEY, store_id TEXT NOT NULL REFERENCES stores(id), name TEXT NOT NULL,
 phone TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL DEFAULT 'parent', updated_at TEXT NOT NULL,lww_key TEXT NOT NULL DEFAULT ''
);
-- @statement
CREATE INDEX customers_store_name ON customers(store_id,name);
-- @statement
CREATE TABLE documents (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 type TEXT NOT NULL CHECK(type IN ('HD','MR','DH','DT','CK')),kind TEXT NOT NULL,
 code TEXT NOT NULL,issued_at TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id),
 customer_id TEXT REFERENCES customers(id),original_id TEXT REFERENCES documents(id),
 subtotal INTEGER NOT NULL CHECK(subtotal>=0 AND typeof(subtotal)='integer'),
 discount INTEGER NOT NULL CHECK(discount>=0 AND discount<=subtotal AND typeof(discount)='integer'),
 total INTEGER NOT NULL CHECK(total=subtotal-discount AND typeof(total)='integer'),
 school_year TEXT NOT NULL,metadata_json TEXT NOT NULL DEFAULT '{}',UNIQUE(store_id,code)
);
-- @statement
CREATE INDEX documents_store_date ON documents(store_id,issued_at);
-- @statement
CREATE TABLE invoice_lines (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),document_id TEXT NOT NULL REFERENCES documents(id),
 variant_id TEXT NOT NULL REFERENCES product_variants(id),name TEXT NOT NULL,size TEXT NOT NULL,color TEXT NOT NULL,unit TEXT NOT NULL,
 quantity INTEGER NOT NULL CHECK(quantity>0 AND typeof(quantity)='integer'),
 unit_price INTEGER NOT NULL CHECK(unit_price>=0 AND typeof(unit_price)='integer'),
 unit_cost INTEGER NOT NULL CHECK(unit_cost>=0 AND typeof(unit_cost)='integer'),
 discount INTEGER NOT NULL CHECK(discount>=0 AND typeof(discount)='integer'),
 price_version TEXT NOT NULL
);
-- @statement
CREATE INDEX lines_store_document ON invoice_lines(store_id,document_id);
-- @statement
CREATE TABLE payments (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 document_id TEXT NOT NULL REFERENCES documents(id),user_id TEXT NOT NULL REFERENCES users(id),
 amount INTEGER NOT NULL CHECK(amount>0 AND typeof(amount)='integer'),
 method TEXT NOT NULL CHECK(method IN ('cash','bank')),direction TEXT NOT NULL CHECK(direction IN ('receive','refund')),
 created_at TEXT NOT NULL,note TEXT NOT NULL DEFAULT ''
);
-- @statement
CREATE INDEX payments_store_document ON payments(store_id,document_id);
-- @statement
CREATE TABLE receivable_entries (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),customer_id TEXT NOT NULL REFERENCES customers(id),
 document_id TEXT NOT NULL REFERENCES documents(id),payment_id TEXT REFERENCES payments(id),
 amount INTEGER NOT NULL CHECK(typeof(amount)='integer'),due_date TEXT NOT NULL,created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX debts_store_document ON receivable_entries(store_id,document_id);
-- @statement
CREATE TABLE document_events (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),document_id TEXT NOT NULL REFERENCES documents(id),
 type TEXT NOT NULL,related_id TEXT REFERENCES documents(id),reason TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id),created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX events_store_document ON document_events(store_id,document_id);
-- @statement
CREATE TABLE held_carts (id TEXT PRIMARY KEY,store_id TEXT NOT NULL,user_id TEXT NOT NULL,name TEXT NOT NULL,payload TEXT NOT NULL,created_at TEXT NOT NULL);
-- @statement
CREATE INDEX carts_store_user ON held_carts(store_id,user_id);
-- @statement
CREATE TABLE variant_price_history (
 variant_id TEXT NOT NULL REFERENCES product_variants(id),version TEXT NOT NULL,price INTEGER NOT NULL,cost INTEGER NOT NULL,
 PRIMARY KEY(variant_id,version)
);
-- @statement
INSERT INTO variant_price_history SELECT id,lww_key,price,cost FROM product_variants;
-- @statement
CREATE TRIGGER price_insert AFTER INSERT ON product_variants BEGIN INSERT OR IGNORE INTO variant_price_history VALUES(NEW.id,NEW.lww_key,NEW.price,NEW.cost); END;
-- @statement
CREATE TRIGGER price_update AFTER UPDATE ON product_variants BEGIN INSERT OR IGNORE INTO variant_price_history VALUES(NEW.id,NEW.lww_key,NEW.price,NEW.cost); END;
-- @statement
CREATE TRIGGER documents_no_update BEFORE UPDATE ON documents BEGIN SELECT RAISE(ABORT,'documents append-only'); END;
-- @statement
CREATE TRIGGER documents_no_delete BEFORE DELETE ON documents BEGIN SELECT RAISE(ABORT,'documents append-only'); END;
-- @statement
CREATE TRIGGER lines_no_update BEFORE UPDATE ON invoice_lines BEGIN SELECT RAISE(ABORT,'invoice_lines append-only'); END;
-- @statement
CREATE TRIGGER lines_no_delete BEFORE DELETE ON invoice_lines BEGIN SELECT RAISE(ABORT,'invoice_lines append-only'); END;
-- @statement
CREATE TRIGGER payments_no_update BEFORE UPDATE ON payments BEGIN SELECT RAISE(ABORT,'payments append-only'); END;
-- @statement
CREATE TRIGGER payments_no_delete BEFORE DELETE ON payments BEGIN SELECT RAISE(ABORT,'payments append-only'); END;
-- @statement
CREATE TRIGGER debt_no_update BEFORE UPDATE ON receivable_entries BEGIN SELECT RAISE(ABORT,'receivable_entries append-only'); END;
-- @statement
CREATE TRIGGER debt_no_delete BEFORE DELETE ON receivable_entries BEGIN SELECT RAISE(ABORT,'receivable_entries append-only'); END;
-- @statement
CREATE TRIGGER events_no_update BEFORE UPDATE ON document_events BEGIN SELECT RAISE(ABORT,'document_events append-only'); END;
-- @statement
CREATE TRIGGER events_no_delete BEFORE DELETE ON document_events BEGIN SELECT RAISE(ABORT,'document_events append-only'); END;
-- @statement
INSERT INTO schema_metadata VALUES (5,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
