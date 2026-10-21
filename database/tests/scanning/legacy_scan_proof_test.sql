BEGIN;
DO $$
DECLARE fx jsonb; foreign_fx jsonb; symbol text; response jsonb; known_user uuid; rotated text:=gen_random_uuid()::text;
BEGIN
 fx:=public.scanner_test_fixture();foreign_fx:=public.scanner_test_fixture();
 SELECT ticket_symbol INTO symbol FROM eshop.tickets WHERE id=(fx#>>'{tickets,0}')::bigint;
 PERFORM public.create_user_for_test('legacy-scan-proof','legacy-scan-proof@example.invalid');
 known_user:=public.get_user_id('legacy-scan-proof');
 INSERT INTO public.occasion_users(occasion,"user") VALUES((fx->>'occasion')::bigint,known_user);
 EXECUTE 'SET LOCAL ROLE anon';
 response:=public.scan_ticket_v2(symbol,fx->>'scan_code');
 PERFORM assert_eq(response->>'code','200','legacy response remains available with its actual scan proof');
 PERFORM assert_true(response ?& ARRAY['ticket','order','products','spot','inventory'],'legacy envelope remains intact');
 response:=public.scan_ticket_v2(symbol,NULL);
 PERFORM assert_eq(response->>'code','401','NULL cannot bypass the legacy scan proof');
 response:=public.scan_ticket_v2(symbol,foreign_fx->>'scan_code');
 PERFORM assert_eq(response->>'code','401','another occasion scan code cannot read this ticket');
 PERFORM assert_true(public.get_all_user_basics_for_scan(fx->>'scan_code') @> jsonb_build_array(jsonb_build_object('id',known_user)),
   'the same proof resolves actual participant scope');
 PERFORM assert_false(has_function_privilege('anon','public.get_scanner_occasion_for_scan_code_internal(text)','EXECUTE'),'technical proof resolver stays private');
 EXECUTE 'RESET ROLE';
 UPDATE public.occasions_hidden SET secret=rotated WHERE id=(SELECT occasion_hidden FROM public.occasions WHERE id=(fx->>'occasion')::bigint);
 EXECUTE 'SET LOCAL ROLE anon';
 PERFORM assert_eq(public.scan_ticket_v2(symbol,fx->>'scan_code')->>'code','401','revoked legacy proof is rejected on the next request');
 PERFORM assert_eq(public.open_scanner_session(fx->>'scan_code')->>'code','401','modern entry uses the same live proof');
 PERFORM assert_eq(public.scan_ticket_v2(symbol,rotated)->>'code','200','rotated proof retains legacy read access');
 EXECUTE 'RESET ROLE';
END $$;
ROLLBACK;
