-- @statement
CREATE TABLE backup_runs (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,device_id TEXT NOT NULL,
 filename TEXT NOT NULL,bytes INTEGER NOT NULL,checksum TEXT NOT NULL,
 created_at TEXT NOT NULL,verified_at TEXT,encrypted INTEGER NOT NULL,status TEXT NOT NULL,message TEXT NOT NULL DEFAULT ''
);
-- @statement
CREATE INDEX backups_store_time ON backup_runs(store_id,created_at);
-- @statement
CREATE TABLE cloud_usage (
 store_id TEXT NOT NULL,device_id TEXT NOT NULL,day TEXT NOT NULL,
 requests INTEGER NOT NULL,rows_read INTEGER NOT NULL,rows_written INTEGER NOT NULL,updated_at TEXT NOT NULL,
 PRIMARY KEY(store_id,device_id,day)
);
-- @statement
CREATE INDEX usage_store_day ON cloud_usage(store_id,day);
-- @statement
ALTER TABLE devices ADD COLUMN installation_hash TEXT;
-- @statement
ALTER TABLE sessions ADD COLUMN installation_hash TEXT NOT NULL DEFAULT '';
-- @statement
CREATE TRIGGER session_device_binding BEFORE INSERT ON sessions WHEN NEW.installation_hash<>'' BEGIN
 SELECT CASE WHEN COALESCE((SELECT installation_hash FROM devices WHERE id=NEW.device_id AND store_id=NEW.store_id),'')<>NEW.installation_hash THEN RAISE(ABORT,'DEVICE_IDENTITY') END;
END;
-- @statement
CREATE TRIGGER audit_server_feed AFTER INSERT ON audit_logs WHEN NEW.chain_index<0 BEGIN
 INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at)
 VALUES(NEW.store_id,'api:'||NEW.id,'audit_logs',NEW.id,
 json_set(json_object('id',NEW.id,'store_id',NEW.store_id,'device_id',NEW.device_id,'user_id',NEW.user_id,'role',NEW.role,'action',NEW.action,'entity_type',NEW.entity_type,'entity_id',NEW.entity_id,'document_code',NEW.document_code,'changes_json',NEW.changes_json,'reason',NEW.reason,'client_time',NEW.client_time,'server_time',NEW.server_time,'app_version',NEW.app_version,'severity',NEW.severity,'hash_prev',NEW.hash_prev),'$.hash',NEW.hash,'$.chain_index',NEW.chain_index),NEW.server_time);
END;
-- @statement
INSERT INTO schema_metadata VALUES (6,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
