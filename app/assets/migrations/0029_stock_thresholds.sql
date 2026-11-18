-- @statement
CREATE TABLE stock_threshold_rules (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 user_id TEXT NOT NULL REFERENCES users(id),variant_id TEXT NOT NULL REFERENCES product_variants(id),
 threshold INTEGER NOT NULL CHECK(typeof(threshold)='integer' AND threshold BETWEEN 0 AND 9007199254740991),
 version_key TEXT NOT NULL UNIQUE,created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX stock_threshold_store_variant_version ON stock_threshold_rules(store_id,variant_id,version_key DESC);
-- @statement
CREATE TRIGGER stock_threshold_scope BEFORE INSERT ON stock_threshold_rules WHEN NOT EXISTS(SELECT 1 FROM devices WHERE id=NEW.device_id AND store_id=NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_REFERENCE_CONFLICT'); END;
-- @statement
CREATE TRIGGER stock_threshold_immutable_update BEFORE UPDATE ON stock_threshold_rules BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- @statement
CREATE TRIGGER stock_threshold_immutable_delete BEFORE DELETE ON stock_threshold_rules BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- @statement
CREATE TRIGGER stock_threshold_cache AFTER INSERT ON stock_threshold_rules WHEN NEW.version_key=(SELECT version_key FROM stock_threshold_rules WHERE store_id=NEW.store_id AND variant_id=NEW.variant_id ORDER BY version_key DESC LIMIT 1) BEGIN
 INSERT INTO store_variant_settings(store_id,variant_id,low_stock_threshold) VALUES(NEW.store_id,NEW.variant_id,NEW.threshold)
 ON CONFLICT(store_id,variant_id) DO UPDATE SET low_stock_threshold=excluded.low_stock_threshold;
END;
-- @statement
INSERT INTO schema_metadata VALUES(29,strftime('%Y-%m-%dT%H:%M:%fZ','now'));

-- @statement
CREATE INDEX audit_store_time_id ON audit_logs(store_id,client_time,id);
