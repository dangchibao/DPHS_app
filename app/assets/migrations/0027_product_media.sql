-- @statement
CREATE TABLE media_objects(id TEXT PRIMARY KEY,mime TEXT NOT NULL,byte_count INTEGER NOT NULL,created_at TEXT NOT NULL);
-- @statement
CREATE TRIGGER media_object_no_update BEFORE UPDATE ON media_objects BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- @statement
CREATE TRIGGER media_object_no_delete BEFORE DELETE ON media_objects BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- Local derived cache; content stays in native backups. D1 uses private R2.
-- @statement
CREATE TABLE media_cache(id TEXT PRIMARY KEY,content BLOB NOT NULL,created_at TEXT NOT NULL);
-- @statement
CREATE TABLE media_outbox(id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),user_id TEXT NOT NULL REFERENCES users(id),hash TEXT NOT NULL,created_at TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,last_error TEXT,next_attempt_at INTEGER NOT NULL DEFAULT 0);
-- @statement
CREATE INDEX media_outbox_store_created ON media_outbox(store_id,created_at,id);
-- @statement
INSERT INTO schema_metadata VALUES(27,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
