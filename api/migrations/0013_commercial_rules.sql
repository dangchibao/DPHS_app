CREATE TABLE commercial_rules (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),name TEXT NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('price_list','promotion')),
 config_json TEXT NOT NULL CHECK(json_valid(config_json)),active INTEGER NOT NULL CHECK(active IN (0,1)),
 updated_at TEXT NOT NULL,lww_key TEXT NOT NULL,UNIQUE(store_id,id)
);
-- @statement
CREATE INDEX commercial_store_kind ON commercial_rules(store_id,kind,active,name);
-- @statement
CREATE TABLE commercial_versions (
 store_id TEXT NOT NULL,rule_id TEXT NOT NULL,version TEXT NOT NULL,name TEXT NOT NULL,kind TEXT NOT NULL,
 config_json TEXT NOT NULL,active INTEGER NOT NULL,updated_at TEXT NOT NULL,
 PRIMARY KEY(store_id,rule_id,version),FOREIGN KEY(store_id,rule_id) REFERENCES commercial_rules(store_id,id)
);
-- @statement
CREATE TRIGGER commercial_version_guard BEFORE INSERT ON commercial_versions WHEN EXISTS(SELECT 1 FROM commercial_versions WHERE store_id=NEW.store_id AND rule_id=NEW.rule_id AND version=NEW.version AND (name<>NEW.name OR kind<>NEW.kind OR config_json<>NEW.config_json OR active<>NEW.active OR updated_at<>NEW.updated_at)) BEGIN SELECT RAISE(ABORT,'COMMERCIAL_VERSION_CONFLICT'); END;
-- @statement
CREATE TRIGGER commercial_insert AFTER INSERT ON commercial_rules BEGIN INSERT OR IGNORE INTO commercial_versions VALUES(NEW.store_id,NEW.id,NEW.lww_key,NEW.name,NEW.kind,NEW.config_json,NEW.active,NEW.updated_at); END;
-- @statement
CREATE TRIGGER commercial_update AFTER UPDATE ON commercial_rules BEGIN INSERT OR IGNORE INTO commercial_versions VALUES(NEW.store_id,NEW.id,NEW.lww_key,NEW.name,NEW.kind,NEW.config_json,NEW.active,NEW.updated_at); END;
-- @statement
CREATE TRIGGER commercial_no_update BEFORE UPDATE ON commercial_versions BEGIN SELECT RAISE(ABORT,'commercial history append-only'); END;
-- @statement
CREATE TRIGGER commercial_no_delete BEFORE DELETE ON commercial_versions BEGIN SELECT RAISE(ABORT,'commercial history append-only'); END;
-- @statement
CREATE TRIGGER commercial_store_identity BEFORE INSERT ON commercial_rules WHEN EXISTS(SELECT 1 FROM commercial_rules WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER commercial_store_fixed BEFORE UPDATE OF store_id ON commercial_rules WHEN NEW.store_id<>OLD.store_id BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
INSERT INTO schema_metadata VALUES(13,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
