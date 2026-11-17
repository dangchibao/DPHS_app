CREATE TABLE return_lines (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),document_id TEXT NOT NULL REFERENCES documents(id),
 original_line_id TEXT NOT NULL REFERENCES invoice_lines(id),quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity BETWEEN 1 AND 100000),
 credit INTEGER NOT NULL CHECK(typeof(credit)='integer' AND credit BETWEEN 0 AND 9007199254740991),
 base_returned INTEGER NOT NULL CHECK(typeof(base_returned)='integer' AND base_returned>=0),
 UNIQUE(store_id,document_id,original_line_id)
);
-- @statement
CREATE INDEX returns_store_original_line ON return_lines(store_id,original_line_id);
-- @statement
CREATE TRIGGER returns_quantity_guard BEFORE INSERT ON return_lines WHEN NOT EXISTS(SELECT 1 FROM return_lines WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents d JOIN invoice_lines l ON l.document_id=d.original_id AND l.store_id=d.store_id JOIN documents o ON o.id=l.document_id AND o.store_id=l.store_id WHERE d.id=NEW.document_id AND d.store_id=NEW.store_id AND d.type='DT' AND l.id=NEW.original_line_id AND o.type IN ('HD','DT')) THEN RAISE(ABORT,'RETURN_REFERENCE_CONFLICT') END;
 SELECT CASE WHEN NEW.base_returned<>COALESCE((SELECT SUM(quantity) FROM return_lines WHERE store_id=NEW.store_id AND original_line_id=NEW.original_line_id),0) OR NEW.base_returned+NEW.quantity>(SELECT quantity FROM invoice_lines WHERE store_id=NEW.store_id AND id=NEW.original_line_id) THEN RAISE(ABORT,'RETURN_QUANTITY_CONFLICT') END;
END;
-- @statement
CREATE TRIGGER returns_store_identity BEFORE INSERT ON return_lines WHEN EXISTS(SELECT 1 FROM return_lines WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER returns_no_update BEFORE UPDATE ON return_lines BEGIN SELECT RAISE(ABORT,'return lines append-only'); END;
-- @statement
CREATE TRIGGER returns_no_delete BEFORE DELETE ON return_lines BEGIN SELECT RAISE(ABORT,'return lines append-only'); END;
-- @statement
CREATE TABLE receivable_adjustments (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),customer_id TEXT NOT NULL REFERENCES customers(id),
 document_id TEXT NOT NULL REFERENCES documents(id),credit_document_id TEXT NOT NULL REFERENCES documents(id),
 amount INTEGER NOT NULL CHECK(typeof(amount)='integer' AND amount BETWEEN -9007199254740991 AND -1),created_at TEXT NOT NULL,
 UNIQUE(store_id,credit_document_id)
);
-- @statement
CREATE INDEX credit_store_document ON receivable_adjustments(store_id,document_id);
-- @statement
CREATE VIEW receivable_ledger AS
 SELECT id,store_id,customer_id,document_id,payment_id,amount,due_date,created_at,'entry' AS entry_kind,NULL AS credit_document_id FROM receivable_entries
 UNION ALL SELECT id,store_id,customer_id,document_id,NULL,amount,'',created_at,'return_credit',credit_document_id FROM receivable_adjustments;
-- @statement
DROP TRIGGER debt_balance_guard;
-- @statement
CREATE TRIGGER debt_balance_guard BEFORE INSERT ON receivable_entries WHEN NEW.amount<0 AND NOT EXISTS(SELECT 1 FROM receivable_entries WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NEW.payment_id IS NULL OR COALESCE((SELECT SUM(amount) FROM receivable_ledger WHERE store_id=NEW.store_id AND document_id=NEW.document_id AND customer_id=NEW.customer_id),0)+NEW.amount<0 THEN RAISE(ABORT,'RECEIVABLE_OVERPAYMENT') END;
END;
-- @statement
CREATE TRIGGER credit_balance_guard BEFORE INSERT ON receivable_adjustments WHEN NOT EXISTS(SELECT 1 FROM receivable_adjustments WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents o JOIN documents d ON d.original_id=o.id AND d.store_id=o.store_id WHERE o.id=NEW.document_id AND o.store_id=NEW.store_id AND o.customer_id=NEW.customer_id AND d.id=NEW.credit_document_id AND d.type='DT' AND d.customer_id=NEW.customer_id) THEN RAISE(ABORT,'RETURN_CREDIT_REFERENCE') END;
 SELECT CASE WHEN COALESCE((SELECT SUM(amount) FROM receivable_ledger WHERE store_id=NEW.store_id AND document_id=NEW.document_id AND customer_id=NEW.customer_id),0)+NEW.amount<0 THEN RAISE(ABORT,'RECEIVABLE_OVERPAYMENT') END;
END;
-- @statement
CREATE TRIGGER credit_store_identity BEFORE INSERT ON receivable_adjustments WHEN EXISTS(SELECT 1 FROM receivable_adjustments WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER credit_no_update BEFORE UPDATE ON receivable_adjustments BEGIN SELECT RAISE(ABORT,'receivable adjustments append-only'); END;
-- @statement
CREATE TRIGGER credit_no_delete BEFORE DELETE ON receivable_adjustments BEGIN SELECT RAISE(ABORT,'receivable adjustments append-only'); END;
-- @statement
CREATE UNIQUE INDEX events_store_cancel ON document_events(store_id,document_id) WHERE type='CANCELLED';
-- @statement
INSERT INTO schema_metadata VALUES(15,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
