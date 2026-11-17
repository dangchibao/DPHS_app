CREATE TABLE tailoring_rules (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),name TEXT NOT NULL,
 config_json TEXT NOT NULL CHECK(json_valid(config_json)),active INTEGER NOT NULL CHECK(active IN (0,1)),
 updated_at TEXT NOT NULL,lww_key TEXT NOT NULL,UNIQUE(store_id,id)
);
-- @statement
CREATE INDEX tailoring_rules_store_active ON tailoring_rules(store_id,active,name);
-- @statement
CREATE TABLE tailoring_versions (
 store_id TEXT NOT NULL,rule_id TEXT NOT NULL,version TEXT NOT NULL,name TEXT NOT NULL,config_json TEXT NOT NULL,
 active INTEGER NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(store_id,rule_id,version),
 FOREIGN KEY(store_id,rule_id) REFERENCES tailoring_rules(store_id,id)
);
-- @statement
CREATE TRIGGER tailoring_history_guard BEFORE INSERT ON tailoring_versions WHEN EXISTS(SELECT 1 FROM tailoring_versions WHERE store_id=NEW.store_id AND rule_id=NEW.rule_id AND version=NEW.version AND (name<>NEW.name OR config_json<>NEW.config_json OR active<>NEW.active OR updated_at<>NEW.updated_at)) BEGIN SELECT RAISE(ABORT,'TAILORING_VERSION_CONFLICT'); END;
-- @statement
CREATE TRIGGER tailoring_rules_insert AFTER INSERT ON tailoring_rules BEGIN INSERT OR IGNORE INTO tailoring_versions VALUES(NEW.store_id,NEW.id,NEW.lww_key,NEW.name,NEW.config_json,NEW.active,NEW.updated_at); END;
-- @statement
CREATE TRIGGER tailoring_rules_update AFTER UPDATE ON tailoring_rules BEGIN INSERT OR IGNORE INTO tailoring_versions VALUES(NEW.store_id,NEW.id,NEW.lww_key,NEW.name,NEW.config_json,NEW.active,NEW.updated_at); END;
-- @statement
CREATE TRIGGER tailoring_history_no_update BEFORE UPDATE ON tailoring_versions BEGIN SELECT RAISE(ABORT,'tailoring history append-only'); END;
-- @statement
CREATE TRIGGER tailoring_history_no_delete BEFORE DELETE ON tailoring_versions BEGIN SELECT RAISE(ABORT,'tailoring history append-only'); END;
-- @statement
CREATE TRIGGER tailoring_store_identity BEFORE INSERT ON tailoring_rules WHEN EXISTS(SELECT 1 FROM tailoring_rules WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER tailoring_store_fixed BEFORE UPDATE OF store_id ON tailoring_rules WHEN NEW.store_id<>OLD.store_id BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE UNIQUE INDEX events_store_tailoring_step ON document_events(store_id,document_id,type) WHERE type IN ('TAILOR_SEWING','TAILOR_READY','TAILOR_DELIVERED');
-- @statement
CREATE TRIGGER events_store_identity BEFORE INSERT ON document_events WHEN EXISTS(SELECT 1 FROM document_events WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER events_store_references BEFORE INSERT ON document_events WHEN NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.document_id AND store_id=NEW.store_id) OR (NEW.related_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.related_id AND store_id=NEW.store_id)) BEGIN SELECT RAISE(ABORT,'STORE_REFERENCE_CONFLICT'); END;
-- @statement
CREATE TRIGGER tailoring_step_guard BEFORE INSERT ON document_events WHEN NEW.type IN ('TAILOR_SEWING','TAILOR_READY','TAILOR_DELIVERED') AND NOT EXISTS(SELECT 1 FROM document_events WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents WHERE store_id=NEW.store_id AND id=NEW.document_id AND type='MR' AND kind='tailoring') THEN RAISE(ABORT,'TAILOR_DOCUMENT_REQUIRED') END;
 SELECT CASE WHEN NEW.type='TAILOR_READY' AND NOT EXISTS(SELECT 1 FROM document_events WHERE store_id=NEW.store_id AND document_id=NEW.document_id AND type='TAILOR_SEWING') THEN RAISE(ABORT,'TAILOR_STEP_ORDER') END;
 SELECT CASE WHEN NEW.type='TAILOR_DELIVERED' AND NOT EXISTS(SELECT 1 FROM document_events WHERE store_id=NEW.store_id AND document_id=NEW.document_id AND type='TAILOR_READY') THEN RAISE(ABORT,'TAILOR_STEP_ORDER') END;
END;
-- @statement
INSERT INTO schema_metadata VALUES(14,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
