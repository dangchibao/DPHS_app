-- @statement
CREATE TABLE bank_accounts (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL UNIQUE REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 user_id TEXT NOT NULL REFERENCES users(id),config_json TEXT NOT NULL CHECK(json_valid(config_json)),
 updated_at TEXT NOT NULL,lww_key TEXT NOT NULL,CHECK(id=store_id)
);
-- @statement
CREATE INDEX bank_accounts_store_updated ON bank_accounts(store_id,updated_at,id);
-- @statement
CREATE TRIGGER bank_account_scope BEFORE INSERT ON bank_accounts WHEN NOT EXISTS(SELECT 1 FROM devices d WHERE d.store_id=NEW.store_id AND d.id=NEW.device_id) BEGIN SELECT RAISE(ABORT,'STORE_REFERENCE_CONFLICT'); END;
-- @statement
CREATE TRIGGER bank_account_identity BEFORE UPDATE ON bank_accounts WHEN OLD.id<>NEW.id OR OLD.store_id<>NEW.store_id OR NOT EXISTS(SELECT 1 FROM devices d WHERE d.store_id=NEW.store_id AND d.id=NEW.device_id) BEGIN SELECT RAISE(ABORT,'STORE_REFERENCE_CONFLICT'); END;
-- @statement
INSERT INTO schema_metadata VALUES(26,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
