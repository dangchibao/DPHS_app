CREATE TRIGGER debt_balance_guard BEFORE INSERT ON receivable_entries
WHEN NEW.amount<0 AND NOT EXISTS(SELECT 1 FROM receivable_entries WHERE id=NEW.id)
BEGIN
 SELECT CASE WHEN NEW.payment_id IS NULL OR COALESCE((SELECT SUM(amount) FROM receivable_entries WHERE store_id=NEW.store_id AND document_id=NEW.document_id AND customer_id=NEW.customer_id),0)+NEW.amount<0 THEN RAISE(ABORT,'RECEIVABLE_OVERPAYMENT') END;
END;
-- @statement
INSERT INTO schema_metadata VALUES (9,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
