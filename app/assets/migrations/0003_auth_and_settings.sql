-- @statement
CREATE TABLE sessions (
 id TEXT PRIMARY KEY, store_id TEXT NOT NULL REFERENCES stores(id), user_id TEXT NOT NULL REFERENCES users(id),
 device_id TEXT NOT NULL REFERENCES devices(id), token_hash TEXT NOT NULL UNIQUE,
 created_at TEXT NOT NULL, expires_at TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0
);
-- @statement
CREATE INDEX sessions_store_user ON sessions(store_id,user_id,revoked);
-- @statement
CREATE TABLE auth_attempts (key TEXT PRIMARY KEY,window_start INTEGER NOT NULL,failures INTEGER NOT NULL);
-- @statement
CREATE TABLE store_settings (store_id TEXT NOT NULL REFERENCES stores(id),key TEXT NOT NULL,value TEXT NOT NULL,PRIMARY KEY(store_id,key));
-- @statement
CREATE TABLE size_chart_rules (
 id TEXT PRIMARY KEY, name TEXT NOT NULL,category TEXT NOT NULL,
 min_height INTEGER NOT NULL,max_height INTEGER NOT NULL,min_weight INTEGER NOT NULL,max_weight INTEGER NOT NULL,
 size TEXT NOT NULL, priority INTEGER NOT NULL DEFAULT 0,
 CHECK(min_height<=max_height),CHECK(min_weight<=max_weight)
);
-- @statement
INSERT INTO schema_metadata VALUES (3,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
