-- Cache cục bộ của timestamp cloud cho bản audit đã được tạo offline.
-- D1 không ghi bảng này; timestamp nằm ngay trên audit/change_feed hiện hữu.
CREATE TABLE local_audit_receipts (
 store_id TEXT NOT NULL,audit_id TEXT NOT NULL REFERENCES audit_logs(id),received_at TEXT NOT NULL,
 PRIMARY KEY(store_id,audit_id)
);
-- @statement
INSERT INTO schema_metadata VALUES(12,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
