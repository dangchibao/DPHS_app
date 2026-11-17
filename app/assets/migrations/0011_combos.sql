CREATE TABLE combo_rules (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),name TEXT NOT NULL,
 price INTEGER NOT NULL CHECK(typeof(price)='integer' AND price>=0 AND price<=9007199254740991),
 items_json TEXT NOT NULL CHECK(json_valid(items_json) AND json_type(items_json)='array' AND json_array_length(items_json) BETWEEN 1 AND 20),
 active INTEGER NOT NULL CHECK(active IN (0,1)),updated_at TEXT NOT NULL,lww_key TEXT NOT NULL,UNIQUE(store_id,id)
);
-- @statement
CREATE INDEX combos_store_active ON combo_rules(store_id,active,name);
-- @statement
CREATE TABLE combo_versions (
 store_id TEXT NOT NULL,combo_id TEXT NOT NULL,version TEXT NOT NULL,name TEXT NOT NULL,price INTEGER NOT NULL,
 items_json TEXT NOT NULL,active INTEGER NOT NULL,updated_at TEXT NOT NULL,
 PRIMARY KEY(store_id,combo_id,version),FOREIGN KEY(store_id,combo_id) REFERENCES combo_rules(store_id,id)
);
-- @statement
CREATE TRIGGER combo_history_guard BEFORE INSERT ON combo_versions WHEN EXISTS(SELECT 1 FROM combo_versions WHERE store_id=NEW.store_id AND combo_id=NEW.combo_id AND version=NEW.version AND (price<>NEW.price OR items_json<>NEW.items_json OR active<>NEW.active OR name<>NEW.name OR updated_at<>NEW.updated_at)) BEGIN SELECT RAISE(ABORT,'COMBO_VERSION_CONFLICT'); END;
-- @statement
CREATE TRIGGER combo_insert AFTER INSERT ON combo_rules BEGIN INSERT OR IGNORE INTO combo_versions VALUES(NEW.store_id,NEW.id,NEW.lww_key,NEW.name,NEW.price,NEW.items_json,NEW.active,NEW.updated_at); END;
-- @statement
CREATE TRIGGER combo_update AFTER UPDATE ON combo_rules BEGIN INSERT OR IGNORE INTO combo_versions VALUES(NEW.store_id,NEW.id,NEW.lww_key,NEW.name,NEW.price,NEW.items_json,NEW.active,NEW.updated_at); END;
-- @statement
CREATE TRIGGER combo_history_no_update BEFORE UPDATE ON combo_versions BEGIN SELECT RAISE(ABORT,'combo history append-only'); END;
-- @statement
CREATE TRIGGER combo_history_no_delete BEFORE DELETE ON combo_versions BEGIN SELECT RAISE(ABORT,'combo history append-only'); END;
-- @statement
CREATE TRIGGER combo_store_identity BEFORE INSERT ON combo_rules WHEN EXISTS(SELECT 1 FROM combo_rules WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER combo_store_fixed BEFORE UPDATE OF store_id ON combo_rules WHEN NEW.store_id<>OLD.store_id BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER variant_product_fixed BEFORE UPDATE OF product_id ON product_variants WHEN NEW.product_id<>OLD.product_id BEGIN SELECT RAISE(ABORT,'VARIANT_PRODUCT_CONFLICT'); END;
-- @statement
CREATE UNIQUE INDEX documents_store_held_cart ON documents(store_id,json_extract(metadata_json,'$.held_cart_id')) WHERE type='HD' AND kind='sale' AND json_extract(metadata_json,'$.held_cart_id') IS NOT NULL;
-- @statement
INSERT INTO schema_metadata VALUES(11,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
