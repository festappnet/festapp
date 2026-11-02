-- Apply only after the ordered-observation Functions bundle is active and verified.
-- No legacy arrival-order writer remains after this contraction.
DROP FUNCTION IF EXISTS public.record_bank_sync_health(bigint,bigint,timestamptz,text,boolean,boolean,boolean);
DROP FUNCTION IF EXISTS public.record_bank_sync_pull(bigint,timestamptz,text);
DROP FUNCTION IF EXISTS public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,text);
