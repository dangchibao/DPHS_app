-- @statement
ALTER TABLE devices ADD COLUMN kind TEXT NOT NULL DEFAULT 'native' CHECK(kind IN ('native','web'));
-- @statement
CREATE TRIGGER device_kind_immutable BEFORE UPDATE OF kind ON devices WHEN NEW.kind<>OLD.kind BEGIN SELECT RAISE(ABORT,'DEVICE_IDENTITY'); END;
-- @statement
CREATE TRIGGER web_stock_forbidden BEFORE INSERT ON stock_movements WHEN EXISTS(SELECT 1 FROM devices WHERE store_id=NEW.store_id AND id=NEW.device_id AND kind='web') BEGIN SELECT RAISE(ABORT,'WEB_STOCK_FORBIDDEN'); END;
-- @statement
CREATE TRIGGER web_allocation_forbidden BEFORE INSERT ON device_stock_allocations WHEN EXISTS(SELECT 1 FROM devices WHERE store_id=NEW.store_id AND id=NEW.device_id AND kind='web') BEGIN SELECT RAISE(ABORT,'WEB_STOCK_FORBIDDEN'); END;
-- @statement
INSERT INTO schema_metadata VALUES(25,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
