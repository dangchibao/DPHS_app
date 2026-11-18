-- @statement
CREATE TABLE audit_archives (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),
 direction INTEGER NOT NULL CHECK(direction IN (-1,1)),first_index INTEGER NOT NULL,last_index INTEGER NOT NULL,
 previous_index INTEGER NOT NULL,previous_hash TEXT NOT NULL,last_hash TEXT NOT NULL,
 source_hash TEXT NOT NULL,source_bytes INTEGER NOT NULL CHECK(source_bytes>0),record_count INTEGER NOT NULL CHECK(record_count>0),
 cutoff TEXT NOT NULL,created_by TEXT NOT NULL REFERENCES users(id),object_key TEXT NOT NULL UNIQUE,
 status TEXT NOT NULL CHECK(status IN ('prepared','verified','committed','cancelled')),
 gzip_hash TEXT,gzip_bytes INTEGER,created_at TEXT NOT NULL,committed_at TEXT,
 CHECK(first_index=previous_index+direction),CHECK(last_index*direction>=first_index*direction)
);
-- @statement
CREATE INDEX audit_archives_store_created ON audit_archives(store_id,created_at,id);
-- @statement
CREATE UNIQUE INDEX audit_archives_store_pending ON audit_archives(store_id,device_id,direction) WHERE status IN ('prepared','verified');
-- @statement
CREATE TRIGGER audit_archives_immutable BEFORE UPDATE ON audit_archives WHEN
 OLD.status IN ('committed','cancelled') OR NEW.id IS NOT OLD.id OR NEW.store_id IS NOT OLD.store_id OR NEW.device_id IS NOT OLD.device_id OR
 NEW.direction IS NOT OLD.direction OR NEW.first_index IS NOT OLD.first_index OR NEW.last_index IS NOT OLD.last_index OR NEW.previous_index IS NOT OLD.previous_index OR
 NEW.previous_hash IS NOT OLD.previous_hash OR NEW.last_hash IS NOT OLD.last_hash OR NEW.source_hash IS NOT OLD.source_hash OR NEW.source_bytes IS NOT OLD.source_bytes OR
 NEW.record_count IS NOT OLD.record_count OR NEW.cutoff IS NOT OLD.cutoff OR NEW.created_by IS NOT OLD.created_by OR NEW.object_key IS NOT OLD.object_key OR NEW.created_at IS NOT OLD.created_at OR
 (OLD.status='verified' AND (NEW.gzip_hash IS NOT OLD.gzip_hash OR NEW.gzip_bytes IS NOT OLD.gzip_bytes)) OR
 NOT ((OLD.status='prepared' AND NEW.status IN ('verified','cancelled')) OR (OLD.status='verified' AND NEW.status IN ('committed','cancelled')))
 BEGIN SELECT RAISE(ABORT,'ARCHIVE_IMMUTABLE'); END;
-- @statement
CREATE TRIGGER audit_archives_no_delete BEFORE DELETE ON audit_archives BEGIN SELECT RAISE(ABORT,'ARCHIVE_IMMUTABLE'); END;
-- @statement
CREATE TABLE audit_chain_checkpoints (
 id TEXT PRIMARY KEY REFERENCES audit_archives(id),store_id TEXT NOT NULL,device_id TEXT NOT NULL,direction INTEGER NOT NULL CHECK(direction IN (-1,1)),
 upto INTEGER NOT NULL CHECK(upto>0),chain_index INTEGER NOT NULL,hash TEXT NOT NULL,created_at TEXT NOT NULL,CHECK(chain_index=direction*upto),UNIQUE(store_id,device_id,direction,upto)
);
-- @statement
CREATE INDEX audit_checkpoint_store_device ON audit_chain_checkpoints(store_id,device_id,direction,upto DESC);
-- @statement
CREATE TRIGGER audit_checkpoint_no_update BEFORE UPDATE ON audit_chain_checkpoints BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- @statement
CREATE TRIGGER audit_checkpoint_no_delete BEFORE DELETE ON audit_chain_checkpoints BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- @statement
CREATE TABLE audit_archive_receipts (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,device_id TEXT NOT NULL,archive_id TEXT NOT NULL REFERENCES audit_archives(id),chain_index INTEGER NOT NULL,record_digest TEXT NOT NULL,
 UNIQUE(store_id,device_id,chain_index)
);
-- @statement
CREATE INDEX audit_receipts_store_archive ON audit_archive_receipts(store_id,archive_id,id);
-- @statement
CREATE INDEX feed_store_audit_entity ON change_feed(store_id,entity_id) WHERE entity_type='audit_logs';
-- @statement
DROP INDEX audit_store_time;
-- @statement
CREATE TRIGGER audit_receipt_no_update BEFORE UPDATE ON audit_archive_receipts BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- @statement
CREATE TRIGGER audit_receipt_no_delete BEFORE DELETE ON audit_archive_receipts BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- @statement
CREATE TABLE audit_archive_guards (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,archive_id TEXT NOT NULL REFERENCES audit_archives(id),valid INTEGER NOT NULL CONSTRAINT audit_archive_valid CHECK(valid=1)
);
-- @statement
CREATE INDEX audit_archive_guard_store ON audit_archive_guards(store_id,archive_id);
-- @statement
DROP TRIGGER audit_no_delete;
-- @statement
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_logs WHEN NOT EXISTS(
 SELECT 1 FROM audit_archive_guards g JOIN audit_archives a ON a.id=g.archive_id
 WHERE g.store_id=OLD.store_id AND g.valid=1 AND a.status='verified' AND a.store_id=OLD.store_id AND a.device_id=OLD.device_id AND
 OLD.chain_index*a.direction BETWEEN a.first_index*a.direction AND a.last_index*a.direction AND
 EXISTS(SELECT 1 FROM audit_archive_receipts r WHERE r.store_id=OLD.store_id AND r.id=OLD.id AND r.device_id=OLD.device_id AND r.archive_id=a.id)
) BEGIN SELECT RAISE(ABORT,'audit_logs append-only'); END;
-- @statement
INSERT INTO schema_metadata VALUES(30,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
