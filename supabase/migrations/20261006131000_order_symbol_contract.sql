BEGIN;
-- Empty disposable databases finish immediately. Production must run the
-- resumable owner-only backfill and verify private mapping before this step.
SET lock_timeout = '5s';
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM eshop.orders WHERE order_symbol IS NULL) THEN
  RAISE EXCEPTION 'order_symbol_backfill_required: run automation/order-symbol/backfill.sql in committed batches';
 END IF;
END $$;
ALTER TABLE eshop.orders VALIDATE CONSTRAINT orders_order_symbol_format_check;
ALTER TABLE eshop.orders ALTER COLUMN order_symbol SET NOT NULL;
DROP FUNCTION IF EXISTS public.backfill_order_symbols(bigint[]);
RESET lock_timeout;

COMMIT;
