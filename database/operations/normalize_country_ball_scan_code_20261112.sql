-- Repair the Country ball code format only, after canonical identity checks.
-- Execute inside a transaction; never output the credential.
SET LOCAL search_path=public,extensions;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='20s';
LOCK TABLE public.occasions_hidden IN SHARE ROW EXCLUSIVE MODE;
DO $$
DECLARE old_secret text; candidate text; bytes bytea; ch integer; i integer;
BEGIN
 SELECT h.secret INTO old_secret FROM public.occasions o
 JOIN public.occasions_hidden h ON h.id=o.occasion_hidden
 WHERE o.id=32316 AND o.organization=3 AND o.occasion_hidden=37
 AND o.title='Country bál 2026' AND o.link='skautskyples2026-copy-ae6d7140'
 FOR UPDATE OF o,h;
 IF NOT FOUND OR (SELECT count(*) FROM public.occasions WHERE occasion_hidden=37)<>1 THEN
   RAISE EXCEPTION 'Country ball exclusive scanner identity does not match';
 END IF;
 IF old_secret ~ '^[A-Z0-9]{5}$' THEN RETURN; END IF;
 IF old_secret !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'Unexpected current scan code format'; END IF;
 LOOP
   candidate:='';
   WHILE length(candidate)<5 LOOP
     bytes:=gen_random_bytes(16);
     FOR i IN 0..15 LOOP
       ch:=get_byte(bytes,i);
       IF ch<252 THEN candidate:=candidate||substr('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',1+(ch%36),1); END IF;
       EXIT WHEN length(candidate)=5;
     END LOOP;
   END LOOP;
   EXIT WHEN NOT EXISTS(SELECT 1 FROM public.occasions_hidden WHERE secret=candidate);
 END LOOP;
 UPDATE public.occasions_hidden SET secret=candidate WHERE id=37;
 UPDATE public.scanner_settings SET epoch=epoch+1 WHERE occasion_id=32316;
 UPDATE public.scanner_sessions SET revoked_at=now() WHERE occasion_id=32316 AND revoked_at IS NULL;
 IF candidate !~ '^[A-Z0-9]{5}$' OR
    (SELECT array_agg(p.id) FROM public.get_scanner_occasion_for_scan_code_internal(candidate) p) IS DISTINCT FROM ARRAY[32316::bigint]
 THEN RAISE EXCEPTION 'Country ball code format/resolution verification failed'; END IF;
END $$;
