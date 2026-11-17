CREATE TABLE payroll_commands (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,device_id TEXT NOT NULL,user_id TEXT NOT NULL,
 kind TEXT NOT NULL,payload_json TEXT NOT NULL,created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX payroll_commands_store_user ON payroll_commands(store_id,user_id,created_at);
-- @statement
CREATE TABLE payroll_results (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,device_id TEXT NOT NULL,user_id TEXT NOT NULL,
 record_hash TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('accepted','rejected')),message TEXT NOT NULL,created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX payroll_results_store_user ON payroll_results(store_id,user_id,created_at);
-- @statement
CREATE TABLE compensation_versions (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,device_id TEXT NOT NULL,user_id TEXT NOT NULL,employee_id TEXT NOT NULL,
 effective_month TEXT NOT NULL,revision INTEGER NOT NULL,previous_id TEXT,config_json TEXT NOT NULL,created_at TEXT NOT NULL,
 UNIQUE(store_id,employee_id,effective_month,revision)
);
-- @statement
CREATE INDEX compensation_store_employee ON compensation_versions(store_id,employee_id,effective_month,revision);
-- @statement
CREATE TABLE payroll_runs (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,device_id TEXT NOT NULL,user_id TEXT NOT NULL,employee_id TEXT NOT NULL,
 employee_name TEXT NOT NULL,period_start TEXT NOT NULL,period_end TEXT NOT NULL,rule_id TEXT NOT NULL,
 config_json TEXT NOT NULL,sources_json TEXT NOT NULL,totals_json TEXT NOT NULL,business_seq INTEGER NOT NULL,private_seq INTEGER NOT NULL,created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX payroll_runs_store_employee ON payroll_runs(store_id,employee_id,period_start,period_end);
-- @statement
CREATE TABLE payroll_voids (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,device_id TEXT NOT NULL,user_id TEXT NOT NULL,run_id TEXT NOT NULL,
 reason TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(store_id,run_id)
);
-- @statement
CREATE INDEX payroll_voids_store_run ON payroll_voids(store_id,run_id);
-- @statement
CREATE TABLE payroll_reconciliations (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,run_id TEXT NOT NULL,document_id TEXT NOT NULL,created_at TEXT NOT NULL,
 UNIQUE(store_id,run_id,document_id)
);
-- @statement
CREATE INDEX payroll_reconciliations_store_run ON payroll_reconciliations(store_id,run_id);
-- @statement
CREATE TABLE payroll_feed (
 server_seq INTEGER PRIMARY KEY AUTOINCREMENT,store_id TEXT NOT NULL,entity_type TEXT NOT NULL,entity_id TEXT NOT NULL,payload TEXT NOT NULL,created_at TEXT NOT NULL
);
-- @statement
CREATE INDEX payroll_feed_store_seq ON payroll_feed(store_id,server_seq);
-- @statement
CREATE TABLE payroll_guards (
 id TEXT PRIMARY KEY,store_id TEXT NOT NULL,expected_business INTEGER NOT NULL,actual_business INTEGER NOT NULL,
 expected_private INTEGER NOT NULL,actual_private INTEGER NOT NULL,
 CHECK(expected_business=actual_business AND expected_private=actual_private)
);
-- @statement
CREATE TABLE sync_checkpoints (
 store_id TEXT NOT NULL,device_id TEXT NOT NULL,day TEXT NOT NULL,received_at TEXT NOT NULL,
 PRIMARY KEY(store_id,device_id,day)
);
-- @statement
CREATE VIEW payroll_sales_source AS
 SELECT store_id,user_id AS employee_id,issued_at,id AS source_id,total AS net_amount FROM documents WHERE type IN ('HD','MR')
 UNION ALL SELECT d.store_id,d.user_id,d.issued_at,l.id,l.quantity*l.unit_price-l.discount FROM documents d JOIN invoice_lines l ON l.store_id=d.store_id AND l.document_id=d.id WHERE d.type='DT'
 UNION ALL SELECT d.store_id,o.user_id,d.issued_at,r.id,-r.credit FROM documents d JOIN return_lines r ON r.store_id=d.store_id AND r.document_id=d.id JOIN invoice_lines l ON l.store_id=r.store_id AND l.id=r.original_line_id JOIN documents o ON o.store_id=l.store_id AND o.id=l.document_id;
-- @statement
CREATE TRIGGER payroll_late_sale AFTER INSERT ON documents WHEN NEW.type IN ('HD','MR') BEGIN
 INSERT OR IGNORE INTO payroll_reconciliations SELECT p.id||':'||NEW.id,p.store_id,p.id,NEW.id,NEW.issued_at FROM payroll_runs p WHERE p.store_id=NEW.store_id AND p.employee_id=NEW.user_id AND substr(datetime(NEW.issued_at,'+7 hours'),1,10)>=p.period_start AND substr(datetime(NEW.issued_at,'+7 hours'),1,10)<p.period_end AND NOT EXISTS(SELECT 1 FROM payroll_voids v WHERE v.store_id=p.store_id AND v.run_id=p.id);
END;
-- @statement
CREATE TRIGGER payroll_late_replacement AFTER INSERT ON invoice_lines WHEN EXISTS(SELECT 1 FROM documents WHERE store_id=NEW.store_id AND id=NEW.document_id AND type='DT') BEGIN
 INSERT OR IGNORE INTO payroll_reconciliations SELECT p.id||':'||d.id,p.store_id,p.id,d.id,d.issued_at FROM payroll_runs p JOIN documents d ON d.store_id=p.store_id AND d.user_id=p.employee_id WHERE d.store_id=NEW.store_id AND d.id=NEW.document_id AND substr(datetime(d.issued_at,'+7 hours'),1,10)>=p.period_start AND substr(datetime(d.issued_at,'+7 hours'),1,10)<p.period_end AND NOT EXISTS(SELECT 1 FROM payroll_voids v WHERE v.store_id=p.store_id AND v.run_id=p.id);
END;
-- @statement
CREATE TRIGGER payroll_late_return AFTER INSERT ON return_lines BEGIN
 INSERT OR IGNORE INTO payroll_reconciliations SELECT p.id||':'||d.id,p.store_id,p.id,d.id,d.issued_at FROM payroll_runs p JOIN documents d ON d.store_id=p.store_id JOIN invoice_lines l ON l.store_id=p.store_id AND l.id=NEW.original_line_id JOIN documents o ON o.store_id=l.store_id AND o.id=l.document_id AND o.user_id=p.employee_id WHERE d.store_id=NEW.store_id AND d.id=NEW.document_id AND substr(datetime(d.issued_at,'+7 hours'),1,10)>=p.period_start AND substr(datetime(d.issued_at,'+7 hours'),1,10)<p.period_end AND NOT EXISTS(SELECT 1 FROM payroll_voids v WHERE v.store_id=p.store_id AND v.run_id=p.id);
END;
-- @statement
CREATE TRIGGER payroll_reconciliation_feed AFTER INSERT ON payroll_reconciliations BEGIN
 INSERT INTO payroll_feed(store_id,entity_type,entity_id,payload,created_at) VALUES(NEW.store_id,'payroll_reconciliations',NEW.id,json_object('id',NEW.id,'store_id',NEW.store_id,'run_id',NEW.run_id,'document_id',NEW.document_id,'created_at',NEW.created_at),NEW.created_at);
END;
-- @statement
INSERT INTO schema_metadata(version,applied_at) VALUES(22,datetime('now'));

-- @statement
CREATE TRIGGER payroll_commands_no_update BEFORE UPDATE ON payroll_commands BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_commands_no_delete BEFORE DELETE ON payroll_commands BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_commands_store_identity BEFORE INSERT ON payroll_commands WHEN EXISTS(SELECT 1 FROM payroll_commands WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;

-- @statement
CREATE TRIGGER payroll_results_no_update BEFORE UPDATE ON payroll_results BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_results_no_delete BEFORE DELETE ON payroll_results BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_results_store_identity BEFORE INSERT ON payroll_results WHEN EXISTS(SELECT 1 FROM payroll_results WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;

-- @statement
CREATE TRIGGER compensation_versions_no_update BEFORE UPDATE ON compensation_versions BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER compensation_versions_no_delete BEFORE DELETE ON compensation_versions BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER compensation_versions_store_identity BEFORE INSERT ON compensation_versions WHEN EXISTS(SELECT 1 FROM compensation_versions WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;

-- @statement
CREATE TRIGGER payroll_runs_no_update BEFORE UPDATE ON payroll_runs BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_runs_no_delete BEFORE DELETE ON payroll_runs BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_runs_store_identity BEFORE INSERT ON payroll_runs WHEN EXISTS(SELECT 1 FROM payroll_runs WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;

-- @statement
CREATE TRIGGER payroll_voids_no_update BEFORE UPDATE ON payroll_voids BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_voids_no_delete BEFORE DELETE ON payroll_voids BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_voids_store_identity BEFORE INSERT ON payroll_voids WHEN EXISTS(SELECT 1 FROM payroll_voids WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;

-- @statement
CREATE TRIGGER payroll_reconciliations_no_update BEFORE UPDATE ON payroll_reconciliations BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_reconciliations_no_delete BEFORE DELETE ON payroll_reconciliations BEGIN SELECT RAISE(ABORT,'payroll append-only'); END;
-- @statement
CREATE TRIGGER payroll_reconciliations_store_identity BEFORE INSERT ON payroll_reconciliations WHEN EXISTS(SELECT 1 FROM payroll_reconciliations WHERE id=NEW.id AND store_id<>NEW.store_id) BEGIN SELECT RAISE(ABORT,'STORE_ID_CONFLICT'); END;
