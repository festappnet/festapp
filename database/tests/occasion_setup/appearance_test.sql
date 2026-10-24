DO $$ DECLARE actor uuid; target bigint; d jsonb; response jsonb; draft_id uuid:=gen_random_uuid(); BEGIN
 SELECT "user",unit INTO actor,target FROM public.unit_users WHERE is_manager OR is_editor LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft_id,target);
 response:=public.get_occasion_setup_ticket_preview(draft_id,(d->>'revision')::bigint,100);
 IF response->'data' IS DISTINCT FROM d->'data' OR response->'abuseLimits' IS NULL THEN RAISE EXCEPTION 'Private preview must use saved draft and document limits'; END IF;
 BEGIN
  PERFORM public.get_occasion_setup_ticket_preview(draft_id,(d->>'revision')::bigint+1,100);
  RAISE EXCEPTION 'Stale draft preview accepted';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.get_occasion_setup_ticket_preview(draft_id,(d->>'revision')::bigint,100);
  RAISE EXCEPTION 'Anonymous draft preview accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
END $$;
