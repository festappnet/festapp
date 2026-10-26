BEGIN;
SET LOCAL lock_timeout = '5s';
-- Run only after pre-expand writer transactions have completed and owner-only
-- residual repair has committed. No allocator runs under this table lock.
LOCK TABLE eshop.orders IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE order_sequence IS NULL) THEN RAISE EXCEPTION 'order_sequence residual backfill required'; END IF;
END $$;
ALTER TABLE eshop.orders VALIDATE CONSTRAINT orders_order_sequence_positive_check;
ALTER TABLE eshop.orders ALTER COLUMN order_sequence SET NOT NULL;
DROP FUNCTION IF EXISTS public.backfill_order_sequences(bigint);
COMMIT;
