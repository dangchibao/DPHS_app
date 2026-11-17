CREATE TABLE attendance_entries (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),user_id TEXT NOT NULL REFERENCES users(id),
 employee_id TEXT NOT NULL REFERENCES users(id),work_day TEXT NOT NULL,day_units INTEGER NOT NULL CHECK(typeof(day_units)='integer' AND day_units BETWEEN 0 AND 2),
 reason TEXT NOT NULL,created_at TEXT NOT NULL,lww_key TEXT NOT NULL
);
-- @statement
CREATE INDEX attendance_store_employee_day ON attendance_entries(store_id,employee_id,work_day,lww_key);
-- @statement
CREATE TABLE attendance_rejections (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),device_id TEXT NOT NULL REFERENCES devices(id),user_id TEXT NOT NULL REFERENCES users(id),
 employee_id TEXT NOT NULL REFERENCES users(id),work_day TEXT NOT NULL,record_hash TEXT NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX attendance_rejections_store_day ON attendance_rejections(store_id,work_day,employee_id);
-- @statement
CREATE TABLE local_attendance_receipts (
 store_id TEXT NOT NULL REFERENCES stores(id),entry_id TEXT NOT NULL REFERENCES attendance_entries(id),received_at TEXT NOT NULL,
 PRIMARY KEY(store_id,entry_id)
);
-- @statement
CREATE TABLE payroll_locks (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),employee_id TEXT NOT NULL REFERENCES users(id),run_id TEXT NOT NULL,
 period_start TEXT NOT NULL,period_end TEXT NOT NULL,created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX payroll_locks_store_employee ON payroll_locks(store_id,employee_id,period_start,period_end);
-- @statement
CREATE TABLE payroll_lock_releases (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES stores(id),run_id TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(store_id,run_id)
);
-- @statement
CREATE TRIGGER attendance_reference_guard BEFORE INSERT ON attendance_entries BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM devices WHERE store_id=NEW.store_id AND id=NEW.device_id) OR NOT EXISTS(SELECT 1 FROM employee_store_assignments WHERE store_id=NEW.store_id AND user_id=NEW.employee_id) THEN RAISE(ABORT,'STORE_REFERENCE_CONFLICT') END;
END;
-- @statement
CREATE TRIGGER attendance_store_identity BEFORE INSERT ON attendance_entries WHEN EXISTS(SELECT 1 FROM attendance_entries WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
-- @statement
CREATE TRIGGER attendance_closed_guard BEFORE INSERT ON attendance_entries WHEN NOT EXISTS(SELECT 1 FROM attendance_entries WHERE id=NEW.id) BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM payroll_locks p WHERE p.store_id=NEW.store_id AND p.employee_id=NEW.employee_id AND p.period_start<=NEW.work_day AND p.period_end>NEW.work_day AND NOT EXISTS(SELECT 1 FROM payroll_lock_releases r WHERE r.store_id=p.store_id AND r.run_id=p.run_id)) THEN RAISE(ABORT,'ATTENDANCE_PERIOD_LOCKED') END;
END;
-- @statement
CREATE TRIGGER attendance_no_update BEFORE UPDATE ON attendance_entries BEGIN SELECT RAISE(ABORT,'attendance append-only'); END;
-- @statement
CREATE TRIGGER attendance_no_delete BEFORE DELETE ON attendance_entries BEGIN SELECT RAISE(ABORT,'attendance append-only'); END;
-- @statement
CREATE TRIGGER attendance_rejection_no_update BEFORE UPDATE ON attendance_rejections BEGIN SELECT RAISE(ABORT,'attendance rejection append-only'); END;
-- @statement
CREATE TRIGGER attendance_rejection_no_delete BEFORE DELETE ON attendance_rejections BEGIN SELECT RAISE(ABORT,'attendance rejection append-only'); END;
-- @statement
CREATE TRIGGER payroll_lock_no_update BEFORE UPDATE ON payroll_locks BEGIN SELECT RAISE(ABORT,'payroll lock append-only'); END;
-- @statement
CREATE TRIGGER payroll_lock_no_delete BEFORE DELETE ON payroll_locks BEGIN SELECT RAISE(ABORT,'payroll lock append-only'); END;
-- @statement
CREATE TRIGGER payroll_unlock_no_update BEFORE UPDATE ON payroll_lock_releases BEGIN SELECT RAISE(ABORT,'payroll unlock append-only'); END;
-- @statement
CREATE TRIGGER payroll_unlock_no_delete BEFORE DELETE ON payroll_lock_releases BEGIN SELECT RAISE(ABORT,'payroll unlock append-only'); END;
-- @statement
INSERT INTO schema_metadata VALUES(21,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
