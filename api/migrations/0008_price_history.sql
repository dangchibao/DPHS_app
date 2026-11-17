-- Một phiên bản giá chỉ có một nội dung, kể cả bản LWW không thắng.
CREATE TRIGGER price_history_guard BEFORE INSERT ON variant_price_history
WHEN EXISTS(SELECT 1 FROM variant_price_history WHERE variant_id=NEW.variant_id AND version=NEW.version AND (price<>NEW.price OR cost<>NEW.cost))
BEGIN SELECT RAISE(ABORT,'PRICE_VERSION_CONFLICT'); END;
-- @statement
CREATE TRIGGER price_history_no_update BEFORE UPDATE ON variant_price_history BEGIN SELECT RAISE(ABORT,'price history append-only'); END;
-- @statement
CREATE TRIGGER price_history_no_delete BEFORE DELETE ON variant_price_history BEGIN SELECT RAISE(ABORT,'price history append-only'); END;
-- @statement
INSERT INTO schema_metadata VALUES (8,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
