CREATE TABLE daily_reports (
 store_id TEXT NOT NULL,day TEXT NOT NULL,school_year TEXT NOT NULL,school_id TEXT NOT NULL,
 metrics_json TEXT NOT NULL CHECK(json_valid(metrics_json) AND json_type(metrics_json)='object'),
 overflow INTEGER NOT NULL DEFAULT 0 CHECK(overflow IN (0,1)),
 PRIMARY KEY(store_id,day,school_year,school_id)
);
-- @statement
CREATE TABLE report_receipts (
 store_id TEXT NOT NULL,document_id TEXT NOT NULL,payment_ids_json TEXT NOT NULL CHECK(json_valid(payment_ids_json) AND json_type(payment_ids_json)='array'),last_token TEXT NOT NULL,
 PRIMARY KEY(store_id,document_id)
);
-- @statement
CREATE TABLE report_cache_state (store_id TEXT PRIMARY KEY,needs_rebuild INTEGER NOT NULL CHECK(needs_rebuild IN (0,1)));
-- @statement
INSERT INTO report_cache_state SELECT s.id,EXISTS(SELECT 1 FROM documents d WHERE d.store_id=s.id AND d.type IN ('HD','MR','DT')) FROM stores s;
-- @statement
CREATE TABLE receivable_report_balances (
 store_id TEXT NOT NULL,document_id TEXT NOT NULL,customer_id TEXT NOT NULL,amount INTEGER NOT NULL CHECK(typeof(amount)='integer'),due_date TEXT NOT NULL,
 PRIMARY KEY(store_id,document_id)
);
-- @statement
CREATE INDEX receivable_reports_unpaid ON receivable_report_balances(store_id,document_id) WHERE amount>0;
-- @statement
INSERT INTO receivable_report_balances SELECT store_id,document_id,customer_id,SUM(amount),COALESCE(MIN(NULLIF(due_date,'')),'') FROM receivable_ledger GROUP BY store_id,document_id,customer_id;
-- @statement
CREATE TRIGGER receivable_report_entry AFTER INSERT ON receivable_entries BEGIN
 INSERT INTO receivable_report_balances VALUES(NEW.store_id,NEW.document_id,NEW.customer_id,NEW.amount,NEW.due_date)
 ON CONFLICT(store_id,document_id) DO UPDATE SET amount=receivable_report_balances.amount+excluded.amount,due_date=CASE WHEN receivable_report_balances.due_date='' THEN excluded.due_date WHEN excluded.due_date<>'' AND excluded.due_date<receivable_report_balances.due_date THEN excluded.due_date ELSE receivable_report_balances.due_date END;
END;
-- @statement
CREATE TRIGGER receivable_report_credit AFTER INSERT ON receivable_adjustments BEGIN
 INSERT INTO receivable_report_balances VALUES(NEW.store_id,NEW.document_id,NEW.customer_id,NEW.amount,'')
 ON CONFLICT(store_id,document_id) DO UPDATE SET amount=receivable_report_balances.amount+excluded.amount;
END;
-- @statement
INSERT INTO schema_metadata(version,applied_at) VALUES(24,datetime('now'));
