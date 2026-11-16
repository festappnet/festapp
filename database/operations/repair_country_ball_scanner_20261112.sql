-- One-off data repair, organization 3 / occasion 32316 only.
-- Run inside an explicit transaction after canonical backend identity checks.
-- Original relationship: occasion_hidden=1, also used by 13, 82 and 11438.
-- The old secret remains untouched. Fetch the new link from the event admin UI.
DO $$
DECLARE
  old_hidden bigint;
  new_hidden bigint;
  new_secret text;
BEGIN
  PERFORM set_config('search_path','public,extensions',true);
  SELECT occasion_hidden INTO old_hidden FROM public.occasions
  WHERE id=32316 AND organization=3 AND title='Country bál 2026'
    AND link='skautskyples2026-copy-ae6d7140'
  FOR UPDATE;
  IF NOT FOUND OR old_hidden IS NULL THEN
    RAISE EXCEPTION 'Country ball identity/scan relationship does not match';
  END IF;
  PERFORM 1 FROM public.occasions_hidden WHERE id=old_hidden FOR UPDATE;
  IF (SELECT count(*) FROM public.occasions WHERE occasion_hidden=old_hidden)>1 THEN
    IF old_hidden<>1 THEN RAISE EXCEPTION 'Unexpected shared scan relationship'; END IF;
    LOOP
      new_secret:=encode(gen_random_bytes(16),'hex');
      EXIT WHEN NOT EXISTS(SELECT 1 FROM public.occasions_hidden WHERE secret=new_secret);
    END LOOP;
    INSERT INTO public.occasions_hidden(secret) VALUES(new_secret) RETURNING id INTO new_hidden;
    UPDATE public.occasions SET occasion_hidden=new_hidden WHERE id=32316;
    UPDATE public.scanner_settings SET epoch=epoch+1 WHERE occasion_id=32316;
    UPDATE public.scanner_sessions SET revoked_at=now() WHERE occasion_id=32316 AND revoked_at IS NULL;
    RAISE NOTICE 'Country ball scanner isolated: old hidden %, new hidden %',old_hidden,new_hidden;
  END IF;
  IF (SELECT array_agg(proof.id ORDER BY proof.id)
      FROM public.occasions o JOIN public.occasions_hidden h ON h.id=o.occasion_hidden
      CROSS JOIN LATERAL public.get_scanner_occasion_for_scan_code_internal(h.secret) proof
      WHERE o.id=32316) IS DISTINCT FROM ARRAY[32316::bigint] THEN
    RAISE EXCEPTION 'Repaired scan code must resolve exclusively to Country ball';
  END IF;
END $$;
