-- @statement
ALTER TABLE sessions ADD COLUMN kind TEXT NOT NULL DEFAULT 'interactive';
-- @statement
ALTER TABLE sessions ADD COLUMN issued_role TEXT NOT NULL DEFAULT 'cashier';
-- @statement
UPDATE sessions SET issued_role=COALESCE((SELECT role FROM employee_store_assignments a WHERE a.store_id=sessions.store_id AND a.user_id=sessions.user_id),'cashier');
-- @statement
ALTER TABLE outbox ADD COLUMN actor_id TEXT;
-- @statement
UPDATE outbox SET actor_id=COALESCE((SELECT json_extract(j.value,'$.row.user_id') FROM json_each(outbox.payload) j WHERE json_extract(j.value,'$.row.user_id') IS NOT NULL LIMIT 1),'admin');
-- @statement
INSERT INTO schema_metadata VALUES (7,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
