CREATE TABLE reservation_lines (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 document_id TEXT NOT NULL REFERENCES documents(id),variant_id TEXT NOT NULL REFERENCES product_variants(id),
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity BETWEEN 1 AND 100000),
 expires_at TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(store_id,document_id,variant_id)
);
-- @statement
CREATE INDEX reservations_store_device_variant ON reservation_lines(store_id,device_id,variant_id,expires_at);
-- @statement
CREATE INDEX reservations_store_expiry ON reservation_lines(store_id,expires_at,document_id);
-- @statement
CREATE TABLE reservation_events (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 document_id TEXT NOT NULL REFERENCES documents(id),kind TEXT NOT NULL CHECK(kind IN ('release','consume')),
 related_document_id TEXT REFERENCES documents(id),user_id TEXT NOT NULL REFERENCES users(id),reason TEXT NOT NULL,created_at TEXT NOT NULL,
 UNIQUE(store_id,document_id)
);
-- @statement
CREATE INDEX reservation_events_store_related ON reservation_events(store_id,related_document_id);
-- @statement
CREATE TRIGGER reservation_reference_guard BEFORE INSERT ON reservation_lines BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents WHERE store_id=NEW.store_id AND id=NEW.document_id AND device_id=NEW.device_id AND type='DH' AND kind='reservation' AND issued_at=NEW.created_at AND json_extract(metadata_json,'$.expires_at')=NEW.expires_at) THEN RAISE(ABORT,'RESERVATION_REFERENCE') END;
END;
-- @statement
CREATE TRIGGER reservation_quantity_guard BEFORE INSERT ON reservation_lines WHEN NOT EXISTS(SELECT 1 FROM reservation_lines WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NEW.quantity+COALESCE((SELECT SUM(r.quantity) FROM reservation_lines r WHERE r.store_id=NEW.store_id AND r.device_id=NEW.device_id AND r.variant_id=NEW.variant_id AND r.created_at<=NEW.created_at AND r.expires_at>NEW.created_at AND NOT EXISTS(SELECT 1 FROM reservation_events e WHERE e.store_id=r.store_id AND e.document_id=r.document_id AND e.created_at<=NEW.created_at)),0)>COALESCE((SELECT quantity FROM device_stock_allocations WHERE store_id=NEW.store_id AND device_id=NEW.device_id AND variant_id=NEW.variant_id),0) THEN RAISE(ABORT,'INSUFFICIENT_AVAILABLE_STOCK') END;
END;
-- @statement
CREATE TRIGGER reservation_store_identity BEFORE INSERT ON reservation_lines WHEN EXISTS(SELECT 1 FROM reservation_lines WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER reservation_no_update BEFORE UPDATE ON reservation_lines BEGIN SELECT RAISE(ABORT,'reservation lines append-only'); END;
-- @statement
CREATE TRIGGER reservation_no_delete BEFORE DELETE ON reservation_lines BEGIN SELECT RAISE(ABORT,'reservation lines append-only'); END;
-- @statement
CREATE TRIGGER reservation_event_guard BEFORE INSERT ON reservation_events WHEN NOT EXISTS(SELECT 1 FROM reservation_events WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents WHERE store_id=NEW.store_id AND id=NEW.document_id AND device_id=NEW.device_id AND type='DH' AND kind='reservation' AND issued_at<=NEW.created_at) THEN RAISE(ABORT,'RESERVATION_REFERENCE') END;
 SELECT CASE WHEN NEW.kind='release' AND NEW.related_document_id IS NOT NULL THEN RAISE(ABORT,'RESERVATION_RELEASE_REFERENCE') END;
 SELECT CASE WHEN NEW.kind='consume' AND NOT EXISTS(SELECT 1 FROM documents h JOIN documents d ON d.id=NEW.document_id AND d.store_id=h.store_id WHERE h.id=NEW.related_document_id AND h.store_id=NEW.store_id AND h.device_id=NEW.device_id AND h.type='HD' AND h.kind='sale' AND json_extract(h.metadata_json,'$.reservation_id')=d.id AND h.issued_at=NEW.created_at AND json_extract(d.metadata_json,'$.expires_at')>NEW.created_at AND (d.customer_id IS NULL OR h.customer_id=d.customer_id)) THEN RAISE(ABORT,'RESERVATION_CONSUME_REFERENCE') END;
 SELECT CASE WHEN NEW.kind='consume' AND EXISTS(SELECT 1 FROM reservation_lines r WHERE r.store_id=NEW.store_id AND r.document_id=NEW.document_id AND r.quantity>COALESCE((SELECT SUM(l.quantity) FROM invoice_lines l WHERE l.store_id=NEW.store_id AND l.document_id=NEW.related_document_id AND l.variant_id=r.variant_id),0)) THEN RAISE(ABORT,'RESERVATION_INCOMPLETE') END;
END;
-- @statement
CREATE TRIGGER reservation_event_store_identity BEFORE INSERT ON reservation_events WHEN EXISTS(SELECT 1 FROM reservation_events WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER reservation_event_no_update BEFORE UPDATE ON reservation_events BEGIN SELECT RAISE(ABORT,'reservation events append-only'); END;
-- @statement
CREATE TRIGGER reservation_event_no_delete BEFORE DELETE ON reservation_events BEGIN SELECT RAISE(ABORT,'reservation events append-only'); END;
-- @statement
DROP TRIGGER stock_guard;
-- @statement
CREATE TRIGGER stock_guard BEFORE INSERT ON stock_movements WHEN NEW.quantity<0 AND NOT EXISTS(SELECT 1 FROM stock_movements WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN COALESCE((SELECT quantity FROM stock_balances WHERE store_id=NEW.store_id AND variant_id=NEW.variant_id),0)+NEW.quantity<0 THEN RAISE(ABORT,'INSUFFICIENT_STOCK') END;
 SELECT CASE WHEN COALESCE((SELECT quantity FROM device_stock_allocations WHERE store_id=NEW.store_id AND device_id=NEW.device_id AND variant_id=NEW.variant_id),0)+NEW.quantity<0 THEN RAISE(ABORT,'INSUFFICIENT_DEVICE_ALLOCATION') END;
 SELECT CASE WHEN COALESCE((SELECT quantity FROM device_stock_allocations WHERE store_id=NEW.store_id AND device_id=NEW.device_id AND variant_id=NEW.variant_id),0)+NEW.quantity-COALESCE((SELECT SUM(r.quantity) FROM reservation_lines r WHERE r.store_id=NEW.store_id AND r.device_id=NEW.device_id AND r.variant_id=NEW.variant_id AND r.created_at<=NEW.created_at AND r.expires_at>NEW.created_at AND NOT EXISTS(SELECT 1 FROM reservation_events e WHERE e.store_id=r.store_id AND e.document_id=r.document_id AND e.created_at<=NEW.created_at)),0)<0 THEN RAISE(ABORT,'INSUFFICIENT_AVAILABLE_STOCK') END;
END;
-- @statement
INSERT INTO schema_metadata VALUES(17,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
