BEGIN;
SET LOCAL lock_timeout='5s';
-- Run one batch per transaction with ON_ERROR_STOP and a protected output file.
-- Result is the private id -> symbol mapping/checkpoint; never commit customer rows.
WITH batch AS MATERIALIZED (
    SELECT id FROM eshop.orders WHERE order_symbol IS NULL
    ORDER BY id LIMIT 1000 FOR UPDATE SKIP LOCKED
)
SELECT * FROM public.backfill_order_symbols(ARRAY(SELECT id FROM batch));

COMMIT;
