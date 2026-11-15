-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Policy foundation; no customer mutation endpoint is installed by this stage.
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); f bigint; oc bigint; field bigint; p jsonb; rev bigint;
BEGIN
 f:=(x->>'form')::bigint; oc:=(x->>'occasion')::bigint;
 PERFORM assert_false(public.customer_order_operation_enabled_internal(f,'cancel'),'missing feature and policy fail closed');
 PERFORM assert_eq(public.customer_order_policy_internal(f),'{"revision":0,"policy":{}}'::jsonb,'existing forms have no delegated writes');
 INSERT INTO public.form_fields(form,title,type,is_ticket_field,is_hidden,"order")
 VALUES(f,'Telephone','phone',false,false,2) RETURNING id INTO field;
 p:=jsonb_build_object('cancel',jsonb_build_object('enabled',true,'allowed_until',now()+interval '1 day',
   'mode','approval_required','reason_required',true,'refund_mode','manual'),
   'edit',jsonb_build_object('enabled',true,'allowed_until',now()+interval '1 day',
   'fields',jsonb_build_array(jsonb_build_object('id',field,'type','phone'))));
 PERFORM public.save_customer_order_policy_internal(f,p);
 PERFORM assert_false(public.customer_order_operation_enabled_internal(f,'cancel'),'policy cannot replace feature');
 UPDATE public.occasions SET features=features||'[{"code":"customer_self_service","is_enabled":true}]'::jsonb WHERE id=oc;
 PERFORM assert_true(public.customer_order_operation_enabled_internal(f,'cancel'),'both explicit policy and feature permit operation policy gate');
 PERFORM assert_false(public.customer_order_operation_enabled_internal(f,'edit'),'submitted answers stay locked even if input requests edits');
 PERFORM assert_eq(public.customer_order_policy_internal(f)#>'{policy,edit,enabled}','false'::jsonb,'saved edit policy stays disabled');
 PERFORM assert_false(public.customer_order_operation_enabled_internal(f,'refund'),'no arbitrary operation');
 PERFORM assert_false(public.customer_order_operation_enabled_internal(f+9999999,'cancel'),'foreign form has no policy');
 SELECT revision INTO rev FROM eshop.customer_order_change_policies WHERE form_id=f;
 PERFORM public.save_customer_order_policy_internal(f,p);
 PERFORM assert_eq((SELECT revision FROM eshop.customer_order_change_policies WHERE form_id=f),rev,'same policy does not advance revision');
 p:=jsonb_set(p,'{cancel,allowed_until}',to_jsonb(now()-interval '1 hour'));
 PERFORM public.save_customer_order_policy_internal(f,p);
 PERFORM assert_false(public.customer_order_operation_enabled_internal(f,'cancel'),'expired policy fails closed');
 PERFORM assert_eq((SELECT revision FROM eshop.customer_order_change_policies WHERE form_id=f),rev+1,'changed policy advances revision');
 BEGIN
  PERFORM public.normalize_customer_order_policy_internal('{"cancel":{"enabled":true}}');
  RAISE EXCEPTION 'missing deadline/mode accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.normalize_customer_order_policy_internal('{"edit":{"enabled":false,"fields":[{"id":1,"type":"email"}]}}');
  RAISE EXCEPTION 'customer email edit accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.save_customer_order_policy_internal(f,jsonb_set(p,'{edit,fields,0,type}','"text"'));
  RAISE EXCEPTION 'field type mismatch accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_false(public.can_manage_customer_order_policy(f,false),'service role is not organizer policy entitlement');
 BEGIN
  PERFORM public.save_customer_order_policy_internal(f,'{}');
  RAISE EXCEPTION 'service role granted customer policy';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
DO $$
DECLARE role_name text; signature text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  FOREACH signature IN ARRAY ARRAY[
   'public.update_order_responses_domain_internal(bigint,jsonb)',
   'public.update_order_detail_responses_domain_internal(bigint,bigint,jsonb,jsonb)',
   'public.cancel_online_order_admission_internal(bigint,text)',
   'public.prepare_order_refund_internal(bigint,text,numeric,uuid,jsonb,bigint[])',
   'public.save_customer_order_policy_internal(bigint,jsonb)',
   'public.customer_order_operation_enabled_internal(bigint,text)'] LOOP
   PERFORM assert_false(has_function_privilege(role_name,signature,'EXECUTE'),role_name||' cannot call private effect '||signature);
  END LOOP;
  PERFORM assert_false(has_table_privilege(role_name,'eshop.customer_order_change_policies','INSERT,UPDATE,DELETE'),role_name||' cannot write policy table');
 END LOOP;
END $$;

-- The admission owner expresses an intent, not a refund observation. Repeated
-- reconciliation of the original received money cannot revive the admission.
DO $$
DECLARE fx jsonb:=public.scanner_test_fixture(1); oc bigint:=(fx->>'occasion')::bigint;
 tid bigint:=(fx#>>'{tickets,0}')::bigint; oid bigint; org bigint; un bigint;
 conn uuid; attempt uuid; pi bigint; before_projection jsonb; receipt jsonb; version bigint;
BEGIN
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE ticket=tid;
 SELECT organization,unit INTO org,un FROM public.occasions WHERE id=oc;
 INSERT INTO public.notification_center_organizations(organization) VALUES(org);
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
 VALUES(org,un,'acct_customerAdmission',false,'connected') RETURNING id INTO conn;
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method,stripe_connection_id)
 VALUES(100,'CZK','stripe',conn) RETURNING id INTO pi;
 UPDATE eshop.orders SET payment_info=pi,price=100,currency_code='CZK' WHERE id=oid;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,
  livemode,amount_minor,currency,order_revision,idempotency_key,reservation_expires_at,state)
 VALUES(oid,pi,org,un,conn,false,10000,'CZK',1,'customer-admission:'||extensions.gen_random_uuid(),now()+interval '30 minutes','paid') RETURNING id INTO attempt;
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'pi_customerAdmission',attempt,'payment',10000,'CZK',now());
 PERFORM public.refresh_payment_info_totals_internal(pi);
 before_projection:=public.provider_order_payment_projection_internal(oid);
 PERFORM public.cancel_online_order_admission_internal(oid,'storno');
 SELECT email_payment_version INTO version FROM eshop.orders WHERE id=oid;
 PERFORM public.cancel_online_order_admission_internal(oid,'storno');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),version,'repeated admission effect is inert');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=tid),'storno','admission invalidated');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),100::numeric,'online cancellation retains original order price');
 PERFORM assert_eq((SELECT amount FROM eshop.payment_info WHERE id=pi),100::numeric,'original provider amount retained');
 PERFORM assert_eq((SELECT payment_info FROM eshop.orders WHERE id=oid),pi,'payment identity retained');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),0::numeric,'admission intent is not returned money');
 PERFORM assert_eq((SELECT count(*) FROM eshop.refund_requests WHERE order_id=oid),0::bigint,'admission owner cannot invent refund obligation');
 receipt:=public.apply_provider_payment_effects_internal('stripe',attempt,'customer-reconcile',before_projection);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno','late receipt does not revive canceled order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=tid),'storno','late receipt does not revive canceled ticket');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE kind='payment_problem' AND occasion=oc),'late receipt becomes visible to staff');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); f bigint:=(x->>'form')::bigint;
 oc bigint:=(x->>'occasion')::bigint; p jsonb; r jsonb; new_form bigint; cmd uuid:=extensions.gen_random_uuid();
 v bigint; config jsonb; epoch bigint;
BEGIN
 p:=jsonb_build_object('cancel',jsonb_build_object('enabled',true,'allowed_until',now()+interval '1 day',
  'mode','approval_required','reason_required',true,'refund_mode','manual'));
 config:=jsonb_build_object('id',f,'occasion',oc,'title','Self-service rules','expected_aggregate_version',0,
  'customer_self_service',p);
 SET LOCAL ROLE authenticated;
 r:=public.update_form_client_sync_v1(config,cmd);
 RESET ROLE;
 PERFORM assert_eq(r->>'code','200','policy saved through canonical receipted form writer');
 PERFORM assert_eq(public.customer_order_policy_internal(f)->'policy',p,'policy projection includes saved approval and reason rules');
 v:=(public.customer_order_policy_internal(f)->>'revision')::bigint;
 SET LOCAL ROLE authenticated;
 r:=public.update_form_client_sync_v1(config,cmd);
 RESET ROLE;
 PERFORM assert_eq((public.customer_order_policy_internal(f)->>'revision')::bigint,v,'form receipt replay does not revise policy');
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',oc,link,true) WHERE id=oc;
 UPDATE public.occasion_users SET is_editor_view=true WHERE occasion=oc AND "user"=(x->>'actor')::uuid;
 r:=public.duplicate_form_to_occasion_client_sync_v1(f,(SELECT link FROM public.occasions WHERE id=oc),extensions.gen_random_uuid());
 new_form:=(r#>>'{data,formId}')::bigint;
 PERFORM assert_true(new_form IS NOT NULL,'actual form copy succeeds');
 PERFORM assert_eq(public.customer_order_policy_internal(new_form),'{"revision":0,"policy":{}}'::jsonb,'copy cannot inherit operation permissions');
 -- A policy containing automatic refunds needs current financial authority,
 -- including before a receipt replay.
 config:=jsonb_set(config,'{customer_self_service,cancel,refund_mode}','"automatic"');
 DELETE FROM public.unit_users WHERE unit=(SELECT unit FROM public.occasions WHERE id=oc) AND "user"=(x->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.update_form_client_sync_v1(config,cmd);
  RAISE EXCEPTION 'financial authority bypassed at receipt';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 -- Test the canonical feature writer, rather than directly mutating its epoch.
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) SELECT unit,(x->>'actor')::uuid,true,true FROM public.occasions WHERE id=oc;
 SELECT customer_self_service_epoch INTO epoch FROM public.occasions WHERE id=oc;
 PERFORM public.update_occasion_internal_v1(jsonb_build_object('id',oc,'features',
   '[{"code":"form","is_enabled":true},{"code":"customer_self_service","is_enabled":true}]'::jsonb));
 PERFORM assert_eq((SELECT customer_self_service_epoch FROM public.occasions WHERE id=oc),epoch+1,'feature enable changes generation');
 PERFORM public.update_occasion_internal_v1(jsonb_build_object('id',oc,'features',
   '[{"code":"form","is_enabled":true},{"code":"customer_self_service","is_enabled":false}]'::jsonb));
 PERFORM assert_eq((SELECT customer_self_service_epoch FROM public.occasions WHERE id=oc),epoch+2,'feature disable invalidates old generation');
 PERFORM assert_false(public.customer_order_operation_enabled_internal(f,'cancel'),'off feature blocks saved operation policy');
 PERFORM assert_eq(public.customer_order_policy_internal(f)->'policy',p,'disable preserves rules for organizer review');
END $$;

DO $$
BEGIN
 PERFORM assert_eq(public.validate_customer_cancellation_reason_internal('{"reason_required":true}','  Schedule conflict  '),'Schedule conflict','required reason is normalized');
 PERFORM assert_true(public.validate_customer_cancellation_reason_internal('{"reason_required":false}',NULL) IS NULL,'optional reason may be absent');
 BEGIN
  PERFORM public.validate_customer_cancellation_reason_internal('{"reason_required":true}','   ');
  RAISE EXCEPTION 'blank required reason accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.validate_customer_cancellation_reason_internal('{"reason_required":false}',repeat('a',2001));
  RAISE EXCEPTION 'oversize reason accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
