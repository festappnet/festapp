-- Owner-only, committed per occasion, after pre-expand writers have finished.
-- No table lock and no modifications of already-issued numbers.
\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_user <> 'postgres' THEN RAISE EXCEPTION 'owner required'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE occasion IS NULL) THEN RAISE EXCEPTION 'NULL occasion requires investigation'; END IF;
END $$;
SELECT format('SELECT public.backfill_order_sequences(%s);', occasion)
FROM eshop.orders WHERE order_sequence IS NULL GROUP BY occasion ORDER BY occasion
\gexec
SELECT count(*) AS remaining_null_sequences FROM eshop.orders WHERE order_sequence IS NULL;
