-- @statement
CREATE TABLE staff_change_requests(
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),user_id TEXT NOT NULL REFERENCES users(id),
 device_id TEXT NOT NULL REFERENCES devices(id),created_by TEXT NOT NULL REFERENCES users(id),
 global_lock INTEGER NOT NULL CHECK(global_lock IN(0,1)),scope_json TEXT NOT NULL CHECK(json_valid(scope_json)),
 payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),snapshot_json TEXT NOT NULL CHECK(json_valid(snapshot_json)),
 status TEXT NOT NULL CHECK(status IN('pending','completed','cancelled')),created_at TEXT NOT NULL,closed_at TEXT
);
-- @statement
CREATE INDEX staff_changes_store_status ON staff_change_requests(store_id,status,user_id,created_at);
-- @statement
CREATE INDEX staff_changes_global_pending ON staff_change_requests(store_id,user_id) WHERE status='pending' AND global_lock=1;
-- @statement
CREATE TABLE staff_change_devices(store_id TEXT NOT NULL REFERENCES stores(id),request_id TEXT NOT NULL REFERENCES staff_change_requests(id),device_id TEXT NOT NULL REFERENCES devices(id),acked_at TEXT,cursor INTEGER,PRIMARY KEY(store_id,request_id,device_id));
-- @statement
CREATE TRIGGER staff_change_immutable BEFORE UPDATE ON staff_change_requests WHEN NEW.id<>OLD.id OR NEW.store_id<>OLD.store_id OR NEW.user_id<>OLD.user_id OR NEW.payload_json<>OLD.payload_json OR NEW.snapshot_json<>OLD.snapshot_json OR NEW.scope_json<>OLD.scope_json OR NEW.global_lock<>OLD.global_lock OR NEW.device_id<>OLD.device_id OR NEW.created_by<>OLD.created_by OR NEW.created_at<>OLD.created_at OR OLD.status<>'pending' BEGIN SELECT RAISE(ABORT,'STAFF_HANDOFF_IMMUTABLE'); END;
-- @statement
CREATE TRIGGER staff_change_no_delete BEFORE DELETE ON staff_change_requests BEGIN SELECT RAISE(ABORT,'APPEND_ONLY'); END;
-- @statement
CREATE TABLE staff_change_guards(id TEXT PRIMARY KEY,store_id TEXT NOT NULL,valid INTEGER NOT NULL,CONSTRAINT staff_handoff_valid CHECK(valid=1));
-- @statement
INSERT INTO schema_metadata VALUES(28,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
