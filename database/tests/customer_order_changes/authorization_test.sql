-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/customer_order_changes/fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.customer_fixture(); other jsonb:=pg_temp.customer_fixture(); token text; payload jsonb; preview jsonb; command uuid:=extensions.gen_random_uuid(); before_data jsonb; changed boolean;
BEGIN
 payload:=jsonb_build_object('order',jsonb_build_object(x->>'field','+420 777 111 222'));token:=pg_temp.customer_cap(x,'edit',payload);
 SELECT data INTO before_data FROM eshop.orders WHERE id=(x->>'order')::bigint;
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 BEGIN
  PERFORM public.customer_order_change_gateway('preview',x->>'readToken',NULL,'edit',payload,command);RAISE EXCEPTION 'read token upgraded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.customer_order_change_gateway('preview',token,NULL,'cancel',payload,command);RAISE EXCEPTION 'different operation accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.customer_order_change_gateway('preview',token,NULL,'edit','{"order":{"email":"attacker@example.invalid"}}',command);RAISE EXCEPTION 'changed proposal accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 preview:=public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);
 RESET ROLE;
 UPDATE eshop.orders SET data=data||'{"phone":"admin update"}' WHERE id=(x->>'order')::bigint;
 SET LOCAL ROLE service_role;
 BEGIN
  PERFORM public.customer_order_change_gateway('command',token,NULL,'edit',payload,command,preview->>'fingerprint');RAISE EXCEPTION 'stale preview accepted';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 RESET ROLE;
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=command),'conflict leaves no committed receipt');
 PERFORM assert_true((SELECT consumed_by IS NULL FROM eshop.customer_order_change_capabilities WHERE token_hash=encode(extensions.digest(token,'sha256'),'hex')),'conflict does not consume capability');
 UPDATE eshop.customer_order_change_capabilities SET organization_id=(other->>'organization')::bigint WHERE token_hash=encode(extensions.digest(token,'sha256'),'hex');
 SET LOCAL ROLE service_role;
 BEGIN PERFORM public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);RAISE EXCEPTION 'foreign tenant credential accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 RESET ROLE;
 token:=pg_temp.customer_cap(x,'edit',payload);
 UPDATE eshop.customer_order_change_capabilities SET expires_at=clock_timestamp()-interval '1 second' WHERE token_hash=encode(extensions.digest(token,'sha256'),'hex');
 SET LOCAL ROLE service_role;
 BEGIN PERFORM public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);RAISE EXCEPTION 'expired accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 RESET ROLE;
 token:=pg_temp.customer_cap(x,'edit',payload);
 UPDATE eshop.waitlist_capabilities SET revoked_at=clock_timestamp() WHERE token_hash=encode(extensions.digest(x->>'readToken','sha256'),'hex');
 SET LOCAL ROLE service_role;
 BEGIN PERFORM public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);RAISE EXCEPTION 'revoked parent accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 RESET ROLE;
 PERFORM assert_eq((SELECT data FROM eshop.orders WHERE id=(other->>'order')::bigint)->>'phone',NULL::text,'foreign order untouched');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.customer_fixture(); payload jsonb; token text; preview jsonb; command uuid:=extensions.gen_random_uuid(); result jsonb;
BEGIN
 payload:=jsonb_build_object('order',jsonb_build_object(x->>'field','123'));token:=pg_temp.customer_cap(x,'edit',payload);
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 preview:=public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);
 result:=public.customer_order_change_gateway('command',token,NULL,'edit',payload,command,preview->>'fingerprint');
 RESET ROLE;
 -- Replay is not a second authorization path around expiry, policy or revocation.
 UPDATE eshop.customer_order_change_capabilities SET expires_at=now()-interval '1 second' WHERE consumed_by=command;
 SET LOCAL ROLE service_role;
 BEGIN PERFORM public.customer_order_change_gateway('command',token,NULL,'edit',payload,command,preview->>'fingerprint');RAISE EXCEPTION 'expired receipt disclosed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 RESET ROLE;
 PERFORM assert_eq((SELECT count(*) FROM eshop.customer_order_change_events WHERE command_id=command),1::bigint,'one effect despite replay denial');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.customer_fixture(); token text; payload jsonb; preview jsonb; command uuid:=extensions.gen_random_uuid(); result jsonb;
BEGIN
 payload:=jsonb_build_object('order',jsonb_build_object(x->>'field','123'));token:=pg_temp.customer_cap(x,'edit',payload);
 UPDATE public.unit_users SET is_editor=true WHERE unit=(SELECT unit FROM public.occasions WHERE id=(x->>'occasion')::bigint) AND "user"=(x->>'actor')::uuid;
 PERFORM public.update_occasion_internal_v1(jsonb_build_object('id',(x->>'occasion')::bigint,'features','[{"code":"form","is_enabled":true},{"code":"customer_self_service","is_enabled":false}]'::jsonb));
 PERFORM public.update_occasion_internal_v1(jsonb_build_object('id',(x->>'occasion')::bigint,'features','[{"code":"form","is_enabled":true},{"code":"customer_self_service","is_enabled":true}]'::jsonb));
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 BEGIN PERFORM public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);RAISE EXCEPTION 'off/on resurrected credential';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 RESET ROLE;
 token:=pg_temp.customer_cap(x,'edit',payload);
 UPDATE eshop.customer_order_change_policies SET revision=revision+1 WHERE form_id=(x->>'form')::bigint;
 SET LOCAL ROLE service_role;
 BEGIN PERFORM public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);RAISE EXCEPTION 'old policy accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 RESET ROLE;
END $$;
DO $$
DECLARE x jsonb:=pg_temp.customer_fixture(); token text; preview jsonb; command uuid:=extensions.gen_random_uuid(); result jsonb; request uuid; at_time timestamptz; policy jsonb;
BEGIN
 policy:=public.customer_order_policy_internal((x->>'form')::bigint)->'policy';
 policy:=jsonb_set(policy,'{cancel,mode}','"approval_required"');
 PERFORM public.save_customer_order_policy_internal((x->>'form')::bigint,policy);
 token:=pg_temp.customer_cap(x,'cancel','{}');
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 preview:=public.customer_order_change_gateway('preview',token,NULL,'cancel','{}',command);
 result:=public.customer_order_change_gateway('command',token,NULL,'cancel','{}',command,preview->>'fingerprint');
 RESET ROLE;
 SELECT id,updated_at INTO request,at_time FROM eshop.customer_order_change_requests WHERE order_id=(x->>'order')::bigint;
 -- Staff retain ordinary authority over previously submitted work, even after
 -- the deadline and feature are disabled. No customer credential is revived.
 UPDATE eshop.customer_order_change_policies p SET revision=p.revision+1,policy=jsonb_set(p.policy,'{cancel,allowed_until}',to_jsonb(now()-interval '1 day')) WHERE form_id=(x->>'form')::bigint;
 UPDATE public.occasions SET features='[]',customer_self_service_epoch=customer_self_service_epoch+1 WHERE id=(x->>'occasion')::bigint;
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 command:=extensions.gen_random_uuid();
 SET LOCAL ROLE authenticated;
 result:=public.command_customer_order_request(request,'approve',command,at_time,'Approved');
 result:=public.command_customer_order_request(request,'approve',command,at_time,'Approved');
 RESET ROLE;
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=(x->>'order')::bigint),'storno','staff can accept earlier request after feature shutdown');
 PERFORM assert_eq((SELECT count(*) FROM eshop.customer_order_change_requests WHERE order_id=(x->>'order')::bigint),1::bigint,'approval does not manufacture another support request');
 PERFORM assert_eq((SELECT count(*) FROM eshop.customer_order_change_events WHERE command_id=command),1::bigint,'staff retry has one effect audit');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.customer_fixture(); other jsonb:=pg_temp.customer_fixture(); token text; payload jsonb; result jsonb; command uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 -- A legitimately issued proposal-bound credential still cannot edit a protected
 -- field or a ticket belonging to another order.
 FOREACH payload IN ARRAY ARRAY[
  '{"order":{"email":"different@example.test"}}'::jsonb,
  jsonb_build_object('tickets',jsonb_build_object(other->>'ticket',jsonb_build_object(x->>'field','123')))
 ] LOOP
  token:=pg_temp.customer_cap(x,'edit',payload);
  SET LOCAL ROLE service_role;
  BEGIN PERFORM public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);RAISE EXCEPTION 'forbidden fields accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  RESET ROLE;
 END LOOP;
 payload:=jsonb_build_object('order',jsonb_build_object(x->>'field','123'));
 token:=pg_temp.customer_cap(x,'edit',payload);
 UPDATE public.form_fields SET is_hidden=true WHERE id=(x->>'field')::bigint;
 SET LOCAL ROLE service_role;
 BEGIN PERFORM public.customer_order_change_gateway('preview',token,NULL,'edit',payload,command);RAISE EXCEPTION 'now-hidden field accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 RESET ROLE;
 -- Invoice repair is represented as support work, never an automatic mutation.
 UPDATE eshop.orders SET data=data||'{"invoice_id":"fixture-existing-invoice"}' WHERE id=(x->>'order')::bigint;
 result:=public.preview_customer_order_change_internal((x->>'order')::bigint,'cancel','{}');
 PERFORM assert_eq(result->>'effect','request_cancel','existing invoice requires staff review');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=(x->>'order')::bigint),'ordered','preview does not cancel invoiced order');
END $$;
