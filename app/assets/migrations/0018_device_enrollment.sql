CREATE TABLE device_enrollments (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 token_hash TEXT NOT NULL UNIQUE,created_at TEXT NOT NULL,expires_at TEXT NOT NULL,
 UNIQUE(store_id,device_id)
);
-- @statement
CREATE INDEX enrollments_store_expiry ON device_enrollments(store_id,expires_at);
-- @statement
CREATE TRIGGER device_identity_immutable BEFORE UPDATE ON devices
WHEN NEW.id<>OLD.id OR NEW.store_id<>OLD.store_id OR NEW.code<>OLD.code OR NEW.created_at<>OLD.created_at OR (OLD.installation_hash IS NOT NULL AND NEW.installation_hash IS NOT OLD.installation_hash)
BEGIN SELECT RAISE(ABORT,'DEVICE_IDENTITY_IMMUTABLE'); END;
-- @statement
CREATE TRIGGER device_revocation_terminal BEFORE UPDATE ON devices WHEN OLD.status='revoked' AND NEW.status<>'revoked'
BEGIN SELECT RAISE(ABORT,'DEVICE_REVOCATION_TERMINAL'); END;
-- @statement
INSERT INTO schema_metadata VALUES(18,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
