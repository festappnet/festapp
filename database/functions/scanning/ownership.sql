-- Atomic historical cleanup and final global ownership constraint.
-- NOWAIT means an active caller aborts this whole migration rather than causing
-- a cross-RPC lock-order deadlock. Retry only after a confirmed rollback.
LOCK TABLE public.occasions,public.occasions_hidden,public.scanner_settings,
 public.scanner_sessions,public.scanner_revoked_credentials IN ACCESS EXCLUSIVE MODE NOWAIT;
DO $$
DECLARE affected record; replacement bigint; candidate text; allocated boolean;
 allowed_organizations bigint[];
BEGIN
 allowed_organizations:=string_to_array(nullif(current_setting('festapp.scanner_ownership_organizations',true),''),',')::bigint[];
 IF EXISTS (SELECT 1 FROM public.occasions o LEFT JOIN public.occasions_hidden h ON h.id=o.occasion_hidden
            WHERE o.occasion_hidden IS NOT NULL AND h.id IS NULL) THEN
   RAISE EXCEPTION 'Scanner ownership contains dangling references';
 END IF;
 CREATE TEMP TABLE scanner_ownership_cutover ON COMMIT DROP AS
 SELECT o.id AS occasion_id,o.organization,o.occasion_hidden AS old_hidden,h.secret AS old_secret
 FROM public.occasions o JOIN public.occasions_hidden h ON h.id=o.occasion_hidden
 WHERE EXISTS (SELECT 1 FROM public.occasions sibling WHERE sibling.occasion_hidden=h.id AND sibling.id<>o.id)
    OR EXISTS (SELECT 1 FROM public.scanner_revoked_credentials r
       WHERE r.secret_hash=encode(extensions.digest(h.secret,'sha256'),'hex'));
 IF EXISTS (SELECT 1 FROM scanner_ownership_cutover c
            WHERE NOT coalesce(c.organization=ANY(allowed_organizations),false)) THEN
   RAISE EXCEPTION 'Scanner ownership repair exceeds the explicit organization scope';
 END IF;
 INSERT INTO public.scanner_revoked_credentials(secret_hash,reason)
 SELECT DISTINCT encode(extensions.digest(old_secret,'sha256'),'hex'),'historical_shared'
 FROM scanner_ownership_cutover WHERE old_secret IS NOT NULL
 ON CONFLICT(secret_hash) DO NOTHING;
 FOR affected IN SELECT * FROM scanner_ownership_cutover ORDER BY occasion_id LOOP
   allocated:=false;
   FOR attempt IN 1..128 LOOP
     candidate:=public.generate_scanner_access_code_internal();
     IF EXISTS (SELECT 1 FROM public.occasions_hidden WHERE secret=candidate)
        OR EXISTS (SELECT 1 FROM public.scanner_revoked_credentials
           WHERE secret_hash=encode(extensions.digest(candidate,'sha256'),'hex')) THEN CONTINUE; END IF;
     INSERT INTO public.occasions_hidden(secret) VALUES(candidate) RETURNING id INTO replacement;
     UPDATE public.occasions SET occasion_hidden=replacement WHERE id=affected.occasion_id;
     allocated:=true; EXIT;
   END LOOP;
   IF NOT allocated THEN RAISE EXCEPTION 'Unable to allocate an independent scanner credential'; END IF;
 END LOOP;
 UPDATE public.scanner_settings SET epoch=epoch+1
 WHERE occasion_id IN (SELECT occasion_id FROM scanner_ownership_cutover);
 UPDATE public.scanner_sessions SET revoked_at=now()
 WHERE occasion_id IN (SELECT occasion_id FROM scanner_ownership_cutover) AND revoked_at IS NULL;
 -- Retain historical row identities, but never retain an active shared bearer.
 UPDATE public.occasions_hidden SET secret=NULL
 WHERE id IN (SELECT old_hidden FROM scanner_ownership_cutover)
   AND NOT EXISTS (SELECT 1 FROM public.occasions o WHERE o.occasion_hidden=occasions_hidden.id);
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.occasions'::regclass
                AND conname='occasions_scanner_credential_unique') THEN
   ALTER TABLE public.occasions ADD CONSTRAINT occasions_scanner_credential_unique UNIQUE(occasion_hidden);
 ELSIF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.occasions'::regclass
        AND conname='occasions_scanner_credential_unique')<>'UNIQUE (occasion_hidden)' THEN
   RAISE EXCEPTION 'Unexpected scanner ownership constraint definition';
 END IF;
 IF EXISTS (SELECT occasion_hidden FROM public.occasions WHERE occasion_hidden IS NOT NULL
            GROUP BY occasion_hidden HAVING count(*)>1) THEN
   RAISE EXCEPTION 'Scanner credential ownership is not unique';
 END IF;
 IF EXISTS (SELECT 1 FROM scanner_ownership_cutover c JOIN public.occasions o ON o.id=c.occasion_id
            JOIN public.occasions_hidden h ON h.id=o.occasion_hidden
            WHERE h.secret IS NULL OR h.secret !~ '^[A-Z0-9]{5}$' OR NOT EXISTS
              (SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(h.secret) p WHERE p.id=o.id)) THEN
   RAISE EXCEPTION 'Repaired scanner credential does not resolve to its own occasion';
 END IF;
 DROP TABLE scanner_ownership_cutover;
END $$;
