PRAGMA foreign_keys = ON;

CREATE TABLE stores (
  id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)), created_at TEXT NOT NULL
);
CREATE TABLE devices (
  id TEXT PRIMARY KEY, store_id TEXT NOT NULL REFERENCES stores(id),
  code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('pending','approved','revoked')),
  created_at TEXT NOT NULL, UNIQUE(store_id, id)
);
CREATE INDEX devices_store_status ON devices(store_id, status);
CREATE TABLE schema_metadata (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
INSERT INTO schema_metadata VALUES (1, strftime('%Y-%m-%dT%H:%M:%fZ','now'));
