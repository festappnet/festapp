BEGIN;
DO $$
DECLARE fx jsonb; session jsonb; result jsonb; ticket bigint; target uuid;
BEGIN
 fx:=public.scanner_test_fixture();ticket:=(fx#>>'{tickets,0}')::bigint;
 session:=(public.open_scanner_session(fx->>'scan_code'))->'data';
 PERFORM assert_false(public.scanner_can_reset_password_internal((fx->>'occasion')::bigint,ticket),'missing app feature hides reset');
 PERFORM create_user_for_test('scanner-reset-capability','scanner-reset-capability@test.local');
 target:=get_user_id('scanner-reset-capability');
 INSERT INTO public.occasion_users(occasion,"user",ticket) VALUES((fx->>'occasion')::bigint,target,ticket);
 UPDATE public.organizations SET data=coalesce(data,'{}'::jsonb)||'{"IS_APP_SUPPORTED":true}'::jsonb
 WHERE id=(SELECT organization FROM public.occasions WHERE id=(fx->>'occasion')::bigint);
 result:=public.lookup_scanner_ticket((session->>'session_id')::uuid,session->>'token',(SELECT ticket_symbol FROM eshop.tickets WHERE id=ticket));
 PERFORM assert_true((result#>>'{data,can_reset_password}')::boolean,'enabled app with ordinary linked account permits reset');
 UPDATE public.occasion_users SET is_editor=true WHERE occasion=(fx->>'occasion')::bigint AND "user"=target;
 PERFORM assert_false(public.scanner_can_reset_password_internal((fx->>'occasion')::bigint,ticket),'privileged targets never expose reset');
 UPDATE public.occasion_users SET is_editor=false WHERE occasion=(fx->>'occasion')::bigint AND "user"=target;
 UPDATE public.organizations SET data=jsonb_set(data,'{IS_APP_SUPPORTED}','false')
 WHERE id=(SELECT organization FROM public.occasions WHERE id=(fx->>'occasion')::bigint);
 BEGIN
  PERFORM public.reset_scanner_password((session->>'session_id')::uuid,session->>'token',ticket,'test-only-value');
  PERFORM assert_fail('disabled app feature must reject reset on server');
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM assert_false(has_function_privilege('anon','public.scanner_can_reset_password_internal(bigint,bigint)','EXECUTE'),'capability helper private');
END $$;
ROLLBACK;
