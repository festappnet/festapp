-- One transaction retains the injected scanner fixture across every DO block.
BEGIN;
DO $$
DECLARE s record; r jsonb;
BEGIN
 PERFORM assert_false(has_function_privilege('anon','public.scanner_session_internal(uuid,text,boolean)','EXECUTE'),'private auth helper revoked');
 PERFORM assert_false(has_function_privilege('authenticated','public.scanner_ticket_projection_internal(bigint,jsonb,bigint)','EXECUTE'),'private projection revoked');
 PERFORM assert_false(has_table_privilege('anon','public.scanner_sessions','SELECT'),'sessions cannot be enumerated');
 PERFORM assert_false(has_table_privilege('authenticated','public.scanner_operations','UPDATE'),'immutable receipts inaccessible directly');
 FOR s IN SELECT occasion_id,config FROM public.scanner_settings LOOP
  BEGIN PERFORM public.get_scanner_settings(s.occasion_id);PERFORM assert_fail('anonymous settings denied');EXCEPTION WHEN insufficient_privilege THEN NULL; WHEN raise_exception THEN IF SQLERRM<>'User is not editor.' THEN RAISE; END IF; END;
 END LOOP;
 BEGIN PERFORM public.scanner_session_internal(gen_random_uuid(),'invalid');PERFORM assert_fail('invalid bearer denied');EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL;END;
END $$;
DO $$
DECLARE a jsonb; b jsonb; sa jsonb; sb jsonb; dto jsonb; snapshot jsonb; response jsonb; original_state text; foreign_ticket bigint;
BEGIN
 a:=public.scanner_test_fixture();b:=public.scanner_test_fixture();
 -- The boundary must hold even between events of the same organization/unit.
 UPDATE public.occasions SET organization=(SELECT organization FROM public.occasions WHERE id=(a->>'occasion')::bigint),unit=(SELECT unit FROM public.occasions WHERE id=(a->>'occasion')::bigint) WHERE id=(b->>'occasion')::bigint;
 sa:=public.open_scanner_session(a->>'scan_code');sb:=public.open_scanner_session(b->>'scan_code');
 snapshot:=public.prepare_scanner_snapshot((sa#>>'{data,session_id}')::uuid,sa#>>'{data,token}');
 response:=public.get_scanner_snapshot_page((sb#>>'{data,session_id}')::uuid,sb#>>'{data,token}',(snapshot#>>'{data,snapshot_id}')::uuid,0);
 PERFORM assert_eq(response->>'code','404','cross-occasion snapshot denied');
 response:=public.lookup_scanner_ticket((sb#>>'{data,session_id}')::uuid,sb#>>'{data,token}',(SELECT ticket_symbol FROM eshop.tickets WHERE id=(a#>>'{tickets,0}')::bigint));
 PERFORM assert_eq(response->>'code','404','cross-occasion lookup denied');
 foreign_ticket:=(a#>>'{tickets,0}')::bigint;
 SELECT state INTO original_state FROM eshop.tickets WHERE id=foreign_ticket;
 dto:=(public.lookup_scanner_ticket((sa#>>'{data,session_id}')::uuid,sa#>>'{data,token}',(SELECT ticket_symbol FROM eshop.tickets WHERE id=foreign_ticket)))->'data';
 response:=public.sync_scanner_operations((sb#>>'{data,session_id}')::uuid,sb#>>'{data,token}',jsonb_build_array(jsonb_build_object(
 'operation_id',gen_random_uuid(),'action','admit_ticket','origin_session_id',sb#>>'{data,session_id}',
 'ticket_id',foreign_ticket,'eligibility_fingerprint',dto->>'eligibility_fingerprint','settings_revision',1,'captured_at',now())));
 PERFORM assert_eq(response#>>'{data,0,outcome}','rejected','forged admission for another event rejected');
 PERFORM assert_eq(response#>>'{data,0,reason}','not_found','foreign ticket details are not disclosed');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=foreign_ticket),original_state,'foreign ticket unchanged');
 UPDATE public.scanner_settings SET config=jsonb_set(config,'{manual_search,tickets}','true') WHERE occasion_id=(b->>'occasion')::bigint;
 response:=public.search_scanner_tickets((sb#>>'{data,session_id}')::uuid,sb#>>'{data,token}',(SELECT ticket_symbol FROM eshop.tickets WHERE id=foreign_ticket));
 PERFORM assert_eq(jsonb_array_length(response->'data'),0,'foreign ticket absent from manual search');
 BEGIN PERFORM public.get_scanner_summary((sa#>>'{data,session_id}')::uuid,sb#>>'{data,token}');PERFORM assert_fail('foreign bearer denied');EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL;END;
END $$;
ROLLBACK;
