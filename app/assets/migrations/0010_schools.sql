CREATE UNIQUE INDEX customers_store_id ON customers(store_id,id);
-- @statement
CREATE TABLE schools (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),name TEXT NOT NULL,
 level TEXT NOT NULL CHECK(level IN ('Mầm non','Tiểu học','THCS','THPT')),
 customer_id TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)),updated_at TEXT NOT NULL,lww_key TEXT NOT NULL,
 UNIQUE(store_id,id),FOREIGN KEY(store_id,customer_id) REFERENCES customers(store_id,id)
);
-- @statement
CREATE INDEX schools_store_name ON schools(store_id,name);
-- @statement
CREATE TABLE school_classes (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),school_id TEXT NOT NULL,
 name TEXT NOT NULL,academic_year TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)),updated_at TEXT NOT NULL,lww_key TEXT NOT NULL,
 UNIQUE(store_id,id),FOREIGN KEY(store_id,school_id) REFERENCES schools(store_id,id)
);
-- @statement
CREATE INDEX classes_store_school ON school_classes(store_id,school_id,academic_year);
-- @statement
CREATE TABLE students (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),class_id TEXT NOT NULL,
 student_code TEXT NOT NULL,name TEXT NOT NULL,customer_id TEXT NOT NULL,
 active INTEGER NOT NULL CHECK(active IN (0,1)),updated_at TEXT NOT NULL,lww_key TEXT NOT NULL,
 FOREIGN KEY(store_id,class_id) REFERENCES school_classes(store_id,id),
 FOREIGN KEY(store_id,customer_id) REFERENCES customers(store_id,id),UNIQUE(store_id,student_code)
);
-- @statement
CREATE INDEX students_store_class ON students(store_id,class_id,name);
-- @statement
CREATE INDEX documents_store_student ON documents(store_id,json_extract(metadata_json,'$.student_id'),issued_at) WHERE json_extract(metadata_json,'$.student_id') IS NOT NULL;
-- @statement
CREATE INDEX documents_store_school ON documents(store_id,json_extract(metadata_json,'$.school_id'),issued_at) WHERE json_extract(metadata_json,'$.school_id') IS NOT NULL;
-- @statement
CREATE TRIGGER customers_store_identity BEFORE INSERT ON customers WHEN EXISTS(SELECT 1 FROM customers WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER schools_store_identity BEFORE INSERT ON schools WHEN EXISTS(SELECT 1 FROM schools WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER classes_store_identity BEFORE INSERT ON school_classes WHEN EXISTS(SELECT 1 FROM school_classes WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER students_store_identity BEFORE INSERT ON students WHEN EXISTS(SELECT 1 FROM students WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER documents_store_identity BEFORE INSERT ON documents WHEN EXISTS(SELECT 1 FROM documents WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER lines_store_identity BEFORE INSERT ON invoice_lines WHEN EXISTS(SELECT 1 FROM invoice_lines WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER payments_store_identity BEFORE INSERT ON payments WHEN EXISTS(SELECT 1 FROM payments WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER debts_store_identity BEFORE INSERT ON receivable_entries WHEN EXISTS(SELECT 1 FROM receivable_entries WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER stock_store_identity BEFORE INSERT ON stock_movements WHEN EXISTS(SELECT 1 FROM stock_movements WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER audit_store_identity BEFORE INSERT ON audit_logs WHEN EXISTS(SELECT 1 FROM audit_logs WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER customers_store_fixed BEFORE UPDATE OF store_id ON customers WHEN NEW.store_id<>OLD.store_id BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER schools_store_fixed BEFORE UPDATE OF store_id ON schools WHEN NEW.store_id<>OLD.store_id BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER classes_store_fixed BEFORE UPDATE OF store_id ON school_classes WHEN NEW.store_id<>OLD.store_id BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER students_store_fixed BEFORE UPDATE OF store_id ON students WHEN NEW.store_id<>OLD.store_id BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER documents_store_references BEFORE INSERT ON documents BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM devices WHERE id=NEW.device_id AND store_id=NEW.store_id) OR (NEW.customer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM customers WHERE id=NEW.customer_id AND store_id=NEW.store_id)) OR (NEW.original_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.original_id AND store_id=NEW.store_id)) THEN RAISE(ABORT,'STORE_REFERENCE_CONFLICT') END;
END;
-- @statement
CREATE TRIGGER lines_store_references BEFORE INSERT ON invoice_lines WHEN NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.document_id AND store_id=NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_REFERENCE_CONFLICT'); END;
-- @statement
CREATE TRIGGER payments_store_references BEFORE INSERT ON payments BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.document_id AND store_id=NEW.store_id) OR NOT EXISTS(SELECT 1 FROM devices WHERE id=NEW.device_id AND store_id=NEW.store_id) THEN RAISE(ABORT,'STORE_REFERENCE_CONFLICT') END;
END;
-- @statement
CREATE TRIGGER debts_store_references BEFORE INSERT ON receivable_entries BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.document_id AND store_id=NEW.store_id) OR NOT EXISTS(SELECT 1 FROM customers WHERE id=NEW.customer_id AND store_id=NEW.store_id) OR (NEW.payment_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM payments WHERE id=NEW.payment_id AND store_id=NEW.store_id)) THEN RAISE(ABORT,'STORE_REFERENCE_CONFLICT') END;
END;
-- @statement
CREATE TRIGGER stock_store_references BEFORE INSERT ON stock_movements BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM devices WHERE id=NEW.device_id AND store_id=NEW.store_id) OR (NEW.document_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM documents WHERE id=NEW.document_id AND store_id=NEW.store_id)) THEN RAISE(ABORT,'STORE_REFERENCE_CONFLICT') END;
END;
-- @statement
CREATE TRIGGER audit_store_references BEFORE INSERT ON audit_logs WHEN NOT EXISTS(SELECT 1 FROM devices WHERE id=NEW.device_id AND store_id=NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_REFERENCE_CONFLICT'); END;
-- @statement
INSERT INTO schema_metadata VALUES (10,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
