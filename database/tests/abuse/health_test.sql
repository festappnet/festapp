DO $$
DECLARE result jsonb;
BEGIN
 PERFORM assert_false(has_function_privilege('anon','public.get_abuse_health_v1()','EXECUTE'),'anonymous cannot inspect operational state');
 PERFORM assert_false(has_function_privilege('authenticated','public.get_abuse_health_v1()','EXECUTE'),'ordinary user cannot inspect operational state');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 EXECUTE 'SET LOCAL ROLE service_role';
 result:=public.get_abuse_health_v1();
 PERFORM assert_eq((result->>'policyRevision')::bigint,1::bigint,'operator health reports the installed revision');
 PERFORM assert_eq((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(result->'queue') k),ARRAY['auth','commitment','ordinary'],'health emits only fixed labels');
 PERFORM assert_eq((result#>>'{queue,ordinary,countCappedAt}')::int,5000,'operator sees bounded count semantics');
 EXECUTE 'RESET ROLE';
END $$;

DO $$ DECLARE token text:=repeat('a',64); result jsonb; BEGIN
 INSERT INTO public.festapp_monitoring_credentials(token_hash,expires_at) VALUES(encode(extensions.digest(token,'sha256'),'hex'),now()+interval '1 hour');
 EXECUTE 'SET LOCAL ROLE anon';
 BEGIN PERFORM public.get_festapp_monitoring_health_v1(repeat('b',64)); RAISE EXCEPTION 'wrong monitor token accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 result:=public.get_festapp_monitoring_health_v1(token);
 PERFORM assert_true(result ? 'abuse','existing monitoring capability includes abuse health');
 PERFORM assert_false(has_function_privilege('anon','public.abuse_health_internal_v1()','EXECUTE'),'anonymous cannot bypass monitoring capability');
 PERFORM assert_false(has_table_privilege('anon','public.festapp_monitoring_credentials','SELECT'),'anonymous cannot read capability hash');
 EXECUTE 'RESET ROLE';
END $$;
