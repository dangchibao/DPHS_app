-- Báo cáo tiền thu theo ngày không quét lại toàn bộ payments mỗi trang.
CREATE INDEX payments_store_created ON payments(store_id,created_at,id);
-- @statement
CREATE TABLE private_access_marks (
 store_id TEXT NOT NULL,session_id TEXT NOT NULL,kind TEXT NOT NULL,accessed_at TEXT NOT NULL,
 PRIMARY KEY(store_id,session_id,kind)
);
-- @statement
INSERT INTO schema_metadata(version,applied_at) VALUES(23,datetime('now'));
