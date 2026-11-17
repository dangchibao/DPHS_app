CREATE TABLE size_rules (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),product_id TEXT REFERENCES products(id),
 name TEXT NOT NULL,config_json TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)),updated_at TEXT NOT NULL,lww_key TEXT NOT NULL DEFAULT ''
);
-- @statement
CREATE INDEX size_rules_store_product ON size_rules(store_id,active,product_id);
-- @statement
CREATE TRIGGER size_rule_store_identity BEFORE INSERT ON size_rules WHEN EXISTS(SELECT 1 FROM size_rules WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER size_rule_store_immutable BEFORE UPDATE ON size_rules WHEN OLD.id<>NEW.id OR OLD.store_id<>NEW.store_id BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
INSERT INTO schema_metadata VALUES(19,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
