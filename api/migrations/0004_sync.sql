-- @statement
CREATE TABLE processed_mutations (
 store_id TEXT NOT NULL, id TEXT NOT NULL, device_id TEXT NOT NULL,
 payload_hash TEXT NOT NULL, received_at TEXT NOT NULL, PRIMARY KEY(store_id,id)
);
-- @statement
CREATE TABLE change_feed (
 server_seq INTEGER PRIMARY KEY AUTOINCREMENT, store_id TEXT NOT NULL,
 mutation_id TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
 payload TEXT NOT NULL, created_at TEXT NOT NULL,
 UNIQUE(store_id,mutation_id,entity_type,entity_id)
);
-- @statement
CREATE INDEX feed_store_seq ON change_feed(store_id,server_seq);
-- @statement
ALTER TABLE products ADD COLUMN lww_key TEXT NOT NULL DEFAULT '';
-- @statement
ALTER TABLE product_variants ADD COLUMN lww_key TEXT NOT NULL DEFAULT '';
-- @statement
ALTER TABLE outbox ADD COLUMN dependencies_json TEXT NOT NULL DEFAULT '[]';
-- @statement
CREATE TRIGGER stock_guard BEFORE INSERT ON stock_movements WHEN NEW.quantity<0 AND NOT EXISTS(SELECT 1 FROM stock_movements WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN COALESCE((SELECT quantity FROM stock_balances WHERE store_id=NEW.store_id AND variant_id=NEW.variant_id),0)+NEW.quantity<0 THEN RAISE(ABORT,'INSUFFICIENT_STOCK') END;
 SELECT CASE WHEN COALESCE((SELECT quantity FROM device_stock_allocations WHERE store_id=NEW.store_id AND device_id=NEW.device_id AND variant_id=NEW.variant_id),0)+NEW.quantity<0 THEN RAISE(ABORT,'INSUFFICIENT_DEVICE_ALLOCATION') END;
END;
-- @statement
CREATE TRIGGER stock_allocate AFTER INSERT ON stock_movements BEGIN
 INSERT INTO device_stock_allocations(store_id,device_id,variant_id,quantity) VALUES(NEW.store_id,NEW.device_id,NEW.variant_id,MAX(0,NEW.quantity))
 ON CONFLICT(store_id,device_id,variant_id) DO UPDATE SET quantity=quantity+NEW.quantity;
END;
-- @statement
INSERT INTO schema_metadata VALUES (4,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
