-- Giới hạn D1: tối đa 32 đối số mỗi hàm SQL, giữ đủ trường null trong audit.
DROP TRIGGER audit_server_feed;
-- @statement
CREATE TRIGGER audit_server_feed AFTER INSERT ON audit_logs WHEN NEW.chain_index<0 BEGIN
 INSERT INTO change_feed(store_id,mutation_id,entity_type,entity_id,payload,created_at)
 VALUES(NEW.store_id,'api:'||NEW.id,'audit_logs',NEW.id,
 json_set(json_object('id',NEW.id,'store_id',NEW.store_id,'device_id',NEW.device_id,'user_id',NEW.user_id,'role',NEW.role,'action',NEW.action,'entity_type',NEW.entity_type,'entity_id',NEW.entity_id,'document_code',NEW.document_code,'changes_json',NEW.changes_json,'reason',NEW.reason,'client_time',NEW.client_time,'server_time',NEW.server_time,'app_version',NEW.app_version,'severity',NEW.severity,'hash_prev',NEW.hash_prev),'$.hash',NEW.hash,'$.chain_index',NEW.chain_index),NEW.server_time);
END;
-- @statement
INSERT INTO schema_metadata VALUES(16,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
