CREATE TABLE transfer_events (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 document_id TEXT NOT NULL REFERENCES documents(id),user_id TEXT NOT NULL REFERENCES users(id),reason TEXT NOT NULL,created_at TEXT NOT NULL,
 UNIQUE(store_id,document_id)
);
-- @statement
CREATE INDEX transfer_events_store_time ON transfer_events(store_id,created_at);
-- @statement
CREATE TABLE transfer_offers (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 source_store_id TEXT NOT NULL,source_device_id TEXT NOT NULL,source_code TEXT NOT NULL,source_store_code TEXT NOT NULL,source_device_code TEXT NOT NULL,
 issued_at TEXT NOT NULL,dispatched_at TEXT NOT NULL,school_year TEXT NOT NULL,items_json TEXT NOT NULL,notes TEXT NOT NULL
);
-- @statement
CREATE INDEX transfer_offers_store_device ON transfer_offers(store_id,device_id,dispatched_at);
-- @statement
CREATE TABLE transfer_receipts (
 id TEXT PRIMARY KEY REFERENCES documents(id),store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 offer_id TEXT NOT NULL REFERENCES transfer_offers(id),user_id TEXT NOT NULL REFERENCES users(id),counts_json TEXT NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL,
 UNIQUE(store_id,offer_id)
);
-- @statement
CREATE INDEX transfer_receipts_store_time ON transfer_receipts(store_id,created_at);
-- @statement
CREATE TABLE transfer_deliveries (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),document_id TEXT NOT NULL REFERENCES documents(id),
 received_store_id TEXT NOT NULL,received_device_id TEXT NOT NULL,receipt_code TEXT NOT NULL,counts_json TEXT NOT NULL,reason TEXT NOT NULL,
 user_id TEXT NOT NULL,receiver_name TEXT NOT NULL,created_at TEXT NOT NULL,
 UNIQUE(store_id,document_id)
);
-- @statement
CREATE INDEX transfer_deliveries_store_time ON transfer_deliveries(store_id,created_at);
-- @statement
CREATE TRIGGER transfer_dispatch_guard BEFORE INSERT ON transfer_events WHEN NOT EXISTS(SELECT 1 FROM transfer_events WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.document_id AND store_id=NEW.store_id AND device_id=NEW.device_id AND type='CK' AND kind='transfer_out' AND issued_at<=NEW.created_at) THEN RAISE(ABORT,'TRANSFER_REFERENCE') END;
END;
-- @statement
CREATE TRIGGER transfer_receipt_guard BEFORE INSERT ON transfer_receipts WHEN NOT EXISTS(SELECT 1 FROM transfer_receipts WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents d JOIN transfer_offers o ON o.id=NEW.offer_id AND o.store_id=d.store_id AND o.device_id=d.device_id WHERE d.id=NEW.id AND d.store_id=NEW.store_id AND d.device_id=NEW.device_id AND d.type='CK' AND d.kind='transfer_in' AND d.issued_at=NEW.created_at AND o.dispatched_at<=NEW.created_at AND json_extract(d.metadata_json,'$.offer_id')=o.id) THEN RAISE(ABORT,'TRANSFER_REFERENCE') END;
END;
-- @statement
CREATE TRIGGER transfer_stock_guard BEFORE INSERT ON stock_movements WHEN NEW.kind IN ('transfer_out','transfer_in') AND NOT EXISTS(SELECT 1 FROM stock_movements WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.document_id AND store_id=NEW.store_id AND device_id=NEW.device_id AND type='CK' AND kind=NEW.kind AND issued_at=NEW.created_at AND user_id=NEW.user_id) THEN RAISE(ABORT,'TRANSFER_REFERENCE') END;
 SELECT CASE WHEN (NEW.kind='transfer_out' AND NEW.quantity>=0) OR (NEW.kind='transfer_in' AND (NEW.quantity<=0 OR NOT EXISTS(SELECT 1 FROM transfer_receipts WHERE store_id=NEW.store_id AND id=NEW.document_id AND device_id=NEW.device_id))) THEN RAISE(ABORT,'TRANSFER_STOCK') END;
END;
-- @statement
CREATE TRIGGER transfer_event_store_identity BEFORE INSERT ON transfer_events WHEN EXISTS(SELECT 1 FROM transfer_events WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER transfer_offer_store_identity BEFORE INSERT ON transfer_offers WHEN EXISTS(SELECT 1 FROM transfer_offers WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER transfer_receipt_store_identity BEFORE INSERT ON transfer_receipts WHEN EXISTS(SELECT 1 FROM transfer_receipts WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER transfer_delivery_store_identity BEFORE INSERT ON transfer_deliveries WHEN EXISTS(SELECT 1 FROM transfer_deliveries WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER transfer_event_no_update BEFORE UPDATE ON transfer_events BEGIN SELECT RAISE(ABORT,'transfer append-only'); END;
-- @statement
CREATE TRIGGER transfer_event_no_delete BEFORE DELETE ON transfer_events BEGIN SELECT RAISE(ABORT,'transfer append-only'); END;
-- @statement
CREATE TRIGGER transfer_offer_no_update BEFORE UPDATE ON transfer_offers BEGIN SELECT RAISE(ABORT,'transfer append-only'); END;
-- @statement
CREATE TRIGGER transfer_offer_no_delete BEFORE DELETE ON transfer_offers BEGIN SELECT RAISE(ABORT,'transfer append-only'); END;
-- @statement
CREATE TRIGGER transfer_receipt_no_update BEFORE UPDATE ON transfer_receipts BEGIN SELECT RAISE(ABORT,'transfer append-only'); END;
-- @statement
CREATE TRIGGER transfer_receipt_no_delete BEFORE DELETE ON transfer_receipts BEGIN SELECT RAISE(ABORT,'transfer append-only'); END;
-- @statement
CREATE TRIGGER transfer_delivery_no_update BEFORE UPDATE ON transfer_deliveries BEGIN SELECT RAISE(ABORT,'transfer append-only'); END;
-- @statement
CREATE TRIGGER transfer_delivery_no_delete BEFORE DELETE ON transfer_deliveries BEGIN SELECT RAISE(ABORT,'transfer append-only'); END;
-- @statement
INSERT INTO schema_metadata VALUES(20,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
