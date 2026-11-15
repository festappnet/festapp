-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Actual read scope, challenge queue, preview, receipt and support request.
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); oid bigint:=(x->>'order')::bigint; fid bigint:=(x->>'form')::bigint; oc bigint:=(x->>'occasion')::bigint;
 read_token text:=repeat('a',64); write_token text:=repeat('b',64); cmd uuid:=extensions.gen_random_uuid(); result jsonb;
 preview jsonb; payload jsonb:='{"reason":"Cannot attend"}'; request uuid; data_before jsonb; expected_at timestamptz;
BEGIN
 UPDATE public.occasions SET features=features||'[{"code":"customer_self_service","is_enabled":true}]' WHERE id=oc;
 INSERT INTO public.notification_center_organizations(organization) VALUES((x->>'organization')::bigint);
 PERFORM public.save_customer_order_policy_internal(fid,jsonb_build_object('cancel',jsonb_build_object('enabled',true,'allowed_until',now()+interval '1 day','mode','approval_required','reason_required',true,'refund_mode','manual')));
 PERFORM public.issue_order_overview_internal(oid,jsonb_build_object('tokenHash',encode(extensions.digest(read_token,'sha256'),'hex'),'contentHash',repeat('a',64),'sealed','{}'::jsonb),extensions.gen_random_uuid());
 SELECT data INTO data_before FROM eshop.orders WHERE id=oid;
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 result:=public.customer_order_change_gateway('challenge_context',read_token,oid,'cancel',payload);
 PERFORM assert_eq(result->>'recipient',(x->>'link')||'@example.invalid','recipient comes from stored order');
 result:=public.customer_order_change_gateway('challenge',read_token,oid,'cancel',payload,NULL,NULL,
  jsonb_build_object('tokenHash',encode(extensions.digest(write_token,'sha256'),'hex'),'contentHash',repeat('b',64),'source','{}'::jsonb,'email','{}'::jsonb),repeat('a',64));
 PERFORM assert_eq(result->>'code','202','challenge enqueues confirmation');
 preview:=public.customer_order_change_gateway('preview',write_token,NULL,'cancel',payload,cmd);
 PERFORM assert_eq(preview->>'effect','request_cancel','approval mode is a request');
 result:=public.customer_order_change_gateway('command',write_token,NULL,'cancel',payload,cmd,preview->>'fingerprint');
 PERFORM assert_eq(result->>'code','200','customer request commits');
 result:=public.customer_order_change_gateway('command',write_token,NULL,'cancel',payload,cmd,preview->>'fingerprint');
 PERFORM assert_eq(result->>'code','200','same identity replays committed result');
 BEGIN PERFORM public.customer_order_change_gateway('command',write_token,NULL,'cancel',payload,cmd,repeat('f',64));RAISE EXCEPTION 'changed command bytes replayed';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.customer_order_change_gateway('command',read_token,oid,'cancel',payload,extensions.gen_random_uuid(),preview->>'fingerprint');RAISE EXCEPTION 'read capability performed write';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 RESET ROLE;
 PERFORM assert_eq((SELECT count(*) FROM eshop.customer_order_change_events WHERE order_id=oid),1::bigint,'retry has one audit');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE dedupe_key='customer-change:'||cmd),1::bigint,'retry has one update email intent');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','request does not cancel order');
 PERFORM assert_eq((SELECT data FROM eshop.orders WHERE id=oid),data_before,'request cannot edit submitted answers');
 SELECT id INTO STRICT request FROM eshop.customer_order_change_requests WHERE order_id=oid;
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE kind='customer_order_request' AND occasion=oc),'request reaches notification center');
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 cmd:=extensions.gen_random_uuid();SELECT updated_at INTO expected_at FROM eshop.customer_order_change_requests WHERE id=request;
 SET LOCAL ROLE authenticated;
 result:=public.command_customer_order_request(request,'reject',cmd,expected_at,'Please contact us');
 RESET ROLE;
 PERFORM assert_eq((SELECT status FROM eshop.customer_order_change_requests WHERE id=request),'rejected','staff rejection recorded');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','rejection preserves order');
END $$;
