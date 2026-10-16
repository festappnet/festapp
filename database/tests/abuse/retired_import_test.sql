DO $$ BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 BEGIN PERFORM public.sync_source_via_http(); RAISE EXCEPTION 'unbounded import still active'; EXCEPTION WHEN feature_not_supported THEN NULL; END;
 BEGIN PERFORM public.setup_external_source('abuse-fixture','https://example.invalid','unused'); RAISE EXCEPTION 'unbounded import setup still active'; EXCEPTION WHEN feature_not_supported THEN NULL; END;
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.external_sync_sources WHERE source_name='abuse-fixture'),'retired setup never persists a new source');
END $$;
