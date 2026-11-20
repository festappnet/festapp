-- Transaction-local tenants and emails; the SQL runner rolls everything back.
CREATE FUNCTION pg_temp.meta_capi_request_fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; other_org bigint; un bigint; spare bigint; manager uuid:=gen_random_uuid();
 admin uuid:=gen_random_uuid(); admin2 uuid:=gen_random_uuid(); no_email uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); editor uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Kulturní platforma','{"DEFAULT_URL":"https://example.invalid/","DEFAULT_LANGUAGE":"en"}') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other platform') RETURNING id INTO other_org;
 INSERT INTO public.units(title,organization) VALUES('Kulturní spolek',org) RETURNING id INTO un;
 -- A second managed Unit lets the manager delete the first one.
 INSERT INTO public.units(title,organization) VALUES('Spare organizer',org) RETURNING id INTO spare;
 INSERT INTO auth.users(id,email) VALUES(manager,manager||'@example.invalid'),(admin,admin||'@example.invalid'),
  (admin2,admin2||'@example.invalid'),(no_email,NULL),(outsider,outsider||'@example.invalid'),(editor,editor||'@example.invalid');
 INSERT INTO public.user_info(id,organization) VALUES(manager,org),(admin,org),(admin2,org),(no_email,org),(outsider,other_org),(editor,org);
 UPDATE public.user_info SET email_readonly=id||'@example.invalid' WHERE id IN (manager,admin,admin2,outsider,editor);
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,manager,true,false),(spare,manager,true,false),(un,editor,false,true);
 UPDATE public.unit_users SET is_editor_view=true WHERE unit=un AND "user"=editor;
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,admin,true),(org,admin2,true),(org,no_email,true),(other_org,outsider,true);
 PERFORM set_config('request.jwt.claim.sub',manager::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 RETURN jsonb_build_object('organization',org,'unit',un,'spare',spare,'manager',manager,'admin',admin,'admin2',admin2,'outsider',outsider,'editor',editor);
END $$;

-- A Unit manager without organization administration asks once; organization
-- administrators are notified and only the platform policy grants Meta CAPI.
DO $$
DECLARE x jsonb:=pg_temp.meta_capi_request_fixture(); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
 r jsonb; m public.email_messages;
BEGIN
 BEGIN PERFORM public.get_unit_meta_purchase(un); RAISE EXCEPTION 'manager read Meta CAPI settings';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM assert_eq(public.get_unit_meta_capi_approval(un),'{"approved":false,"requested_at":null,"request_state":"not_requested","can_request":true}'::jsonb,'missing platform policy is requestable');
 r:=public.request_unit_meta_capi_approval(un);
 PERFORM assert_eq(r->>'request_state','requested','request is active');
 PERFORM assert_true(r->>'requested_at' IS NOT NULL,'request returns persisted date');
 PERFORM assert_false((r->>'can_request')::boolean,'active request cannot be repeated');
 PERFORM assert_eq((SELECT requested_by FROM analytics.organization_meta_capi_request WHERE unit=un),(x->>'manager')::uuid,'request records its actor');
 PERFORM assert_eq(public.get_unit_meta_capi_approval(un),r,'reload reads the persisted status');
 PERFORM assert_eq(public.request_unit_meta_capi_approval(un),r,'retry returns identical status');
 PERFORM assert_eq(public.request_unit_meta_capi_approval((x->>'spare')::bigint),r,'another Unit shares the pending organization request');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND code='META_CAPI_APPROVAL_REQUEST'),2::bigint,'another Unit does not send duplicate mail');
 PERFORM assert_eq((SELECT revision FROM analytics.organization_meta_capi_request WHERE unit=un),1,'retry creates no generation');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.unit_measurement_request WHERE unit=un),'measurement request remains independent');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND unit=un AND code='META_CAPI_APPROVAL_REQUEST'),2::bigint,'every admin with a delivery email receives one notice');
 FOR m IN SELECT * FROM public.email_messages WHERE organization=org AND unit=un AND code='META_CAPI_APPROVAL_REQUEST' LOOP
  PERFORM assert_true(m.recipient_user IN ((x->>'admin')::uuid,(x->>'admin2')::uuid),'no manager, editor or other tenant admin receives notice');
  PERFORM assert_eq(m.recipient,public.get_user_delivery_email(m.recipient_user),'canonical delivery email');
  PERFORM assert_eq(m.message_kind,'custom'::text,'existing email queue');
  PERFORM assert_eq(m.dedupe_key,'meta-capi-approval:'||un||':'||m.recipient_user||':1','per Unit, admin and generation dedupe');
  PERFORM assert_eq(m.data->>'request_revision','1'::text,'request generation');
  PERFORM assert_eq(m.data->>'unit_title','Kulturní spolek'::text,'Unit title');
  PERFORM assert_eq(m.data->>'organization_title','Kulturní platforma'::text,'platform title');
  PERFORM assert_eq(m.data->>'review_url','https://example.invalid/organizationEdit/'||org,'validated tenant review origin');
  PERFORM assert_eq(m.data->>'lang','en'::text,'tenant language');
  PERFORM assert_eq(m.tracking_policy,'disabled'::text,'private admin mail has no tracking');
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM assert_true(public.email_intent_valid(m),'pending request is deliverable');
  UPDATE public.organization_users SET is_admin=false WHERE organization=org AND "user"=m.recipient_user;
  PERFORM assert_false(public.email_intent_valid(m),'removed admin cannot receive private mail');
  UPDATE public.organization_users SET is_admin=true WHERE organization=org AND "user"=m.recipient_user;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
 END LOOP;
 -- Measurement approval alone does not approve Meta CAPI.
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'test','measurement approval');
 PERFORM assert_eq(public.get_unit_meta_capi_approval(un)->'approved','false'::jsonb,'measurement policy is a separate decision');
 UPDATE analytics.organization_policy SET meta_capi_enabled=true WHERE organization=org;
 r:=public.get_unit_meta_capi_approval(un);
 PERFORM assert_eq(r->'approved','true'::jsonb,'platform policy approves');
 PERFORM assert_false((r->>'can_request')::boolean,'approved Unit cannot request');
 SELECT * INTO m FROM public.email_messages WHERE organization=org AND unit=un AND code='META_CAPI_APPROVAL_REQUEST' LIMIT 1;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_false(public.email_intent_valid(m),'already approved request mail is obsolete');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_eq(public.request_unit_meta_capi_approval(un)->'approved','true'::jsonb,'approved request is a no-op');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND code='META_CAPI_APPROVAL_REQUEST'),2::bigint,'approval and retries send no more mail');
 BEGIN PERFORM public.get_unit_meta_purchase(un); RAISE EXCEPTION 'approval granted manager settings access';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.delete_unit(un);
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.organization_meta_capi_request WHERE unit=un),'Unit deletion cascades request');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND code='META_CAPI_APPROVAL_REQUEST' AND unit IS NULL AND workflow_state='cancelled'),2::bigint,'deletion cancels queued requests and detaches Unit');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.meta_capi_request_fixture(); un bigint:=(x->>'unit')::bigint; actor text; role_name text; op text;
BEGIN
 FOR actor IN SELECT unnest(ARRAY[x->>'outsider',x->>'editor','']) LOOP
  PERFORM set_config('request.jwt.claim.sub',actor,true);
  BEGIN PERFORM public.request_unit_meta_capi_approval(un); RAISE EXCEPTION 'unauthorized request'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 FOR actor IN SELECT unnest(ARRAY[x->>'outsider','']) LOOP
  PERFORM set_config('request.jwt.claim.sub',actor,true);
  BEGIN PERFORM public.get_unit_meta_capi_approval(un); RAISE EXCEPTION 'unauthorized read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',x->>'editor',true);
 PERFORM assert_eq(public.get_unit_meta_capi_approval(un)->>'request_state','not_requested','Unit editor can read status');
 PERFORM assert_false((public.get_unit_meta_capi_approval(un)->>'can_request')::boolean,'editor cannot request in the read contract');
 PERFORM set_config('request.jwt.claim.sub',x->>'manager',true);
 PERFORM public.request_unit_meta_capi_approval(un);
 UPDATE public.unit_users SET is_manager=false WHERE unit=un AND "user"=(x->>'manager')::uuid;
 BEGIN PERFORM public.request_unit_meta_capi_approval(un); RAISE EXCEPTION 'unauthorized replay'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  FOREACH op IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   PERFORM assert_false(has_table_privilege(role_name,'analytics.organization_meta_capi_request',op),'no direct request table access');
  END LOOP;
  PERFORM assert_false(has_function_privilege(role_name,'public.unit_meta_capi_approval_internal(bigint)','EXECUTE'),'internal status is private');
  PERFORM assert_eq(has_function_privilege(role_name,'public.request_unit_meta_capi_approval(bigint)','EXECUTE'),role_name='authenticated','request RPC is authenticated only');
  PERFORM assert_eq(has_function_privilege(role_name,'public.get_unit_meta_capi_approval(bigint)','EXECUTE'),role_name='authenticated','read RPC is authenticated only');
 END LOOP;
 PERFORM assert_true((SELECT relrowsecurity FROM pg_class WHERE oid='analytics.organization_meta_capi_request'::regclass),'request table has RLS');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.meta_capi_request_fixture(); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint; oc bigint; bank bigint; unsafe_origin text;
BEGIN
 FOREACH unsafe_origin IN ARRAY ARRAY['http://example.invalid','https://user@example.invalid','https://example.invalid:99999'] LOOP
  UPDATE public.organizations SET data=jsonb_build_object('DEFAULT_URL',unsafe_origin) WHERE id=org;
  BEGIN PERFORM public.request_unit_meta_capi_approval(un); RAISE EXCEPTION 'unsafe origin accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'meta_capi_notification_origin_missing' THEN RAISE; END IF; END;
 END LOOP;
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.organization_meta_capi_request WHERE unit=un),'failure leaves request retryable');
 UPDATE public.organizations SET data='{"DEFAULT_URL":"https://example.invalid"}' WHERE id=org;
 -- Only an admin without a delivery e-mail remains: nobody can be notified.
 UPDATE public.organization_users SET is_admin=false WHERE organization=org AND "user" IN ((x->>'admin')::uuid,(x->>'admin2')::uuid);
 BEGIN PERFORM public.request_unit_meta_capi_approval(un); RAISE EXCEPTION 'request without recipient accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'meta_capi_request_no_recipient' THEN RAISE; END IF; END;
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.organization_meta_capi_request WHERE unit=un),'no recipient leaves the request retryable');
 UPDATE public.organization_users SET is_admin=true WHERE organization=org AND "user"=(x->>'admin')::uuid;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time)
 VALUES('Demo request',un,org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Demo request','CASH') RETURNING id INTO bank;
 INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,sort_order,description,reference_at)
 VALUES(oc,org,'ball','meta-capi-request-test',bank,0,'Synthetic',now());
 PERFORM assert_true(public.is_demo_unit(un),'demo fixture');
 UPDATE public.unit_users SET is_editor_view=true WHERE unit=un AND "user"=(x->>'manager')::uuid;
 PERFORM assert_false((public.request_unit_meta_capi_approval(un)->>'can_request')::boolean,'demo Unit is a no-op');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.organization_meta_capi_request WHERE unit=un),'demo Unit creates no request');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages WHERE organization=org AND code='META_CAPI_APPROVAL_REQUEST'),'failed and demo requests send no mail');
 PERFORM public.request_unit_meta_capi_approval((x->>'spare')::bigint);
 PERFORM assert_eq(public.get_unit_meta_capi_approval(un),
  '{"approved":false,"requested_at":null,"request_state":"not_requested","can_request":false}'::jsonb,
  'demo readers cannot see the live organization request');
 PERFORM set_config('request.jwt.claim.sub',x->>'outsider',true);
 BEGIN PERFORM public.request_unit_meta_capi_approval(un); RAISE EXCEPTION 'unauthorized demo request'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

-- Undelivered or revoked generations can be retried exactly once per generation.
DO $$
DECLARE x jsonb:=pg_temp.meta_capi_request_fixture(); un bigint:=(x->>'unit')::bigint;
 org bigint:=(x->>'organization')::bigint; r jsonb; state text; claimed jsonb;
BEGIN
 PERFORM public.request_unit_meta_capi_approval(un);
 INSERT INTO analytics.organization_policy(organization,meta_capi_enabled,revision,operator,reason) VALUES(org,true,1,'test','approval');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 -- Defer other transaction-local fixtures; exercise the real worker boundary.
 UPDATE public.email_messages SET target_time='infinity' WHERE unit IS DISTINCT FROM un;
 UPDATE public.email_capacity SET paused=false,quota_at=now(),circuit_until=NULL,max_preparing=2,worker_url=NULL;
 FOR i IN 1..2 LOOP
  claimed:=public.claim_email();
  PERFORM assert_eq(claimed,'{"skipped":true}'::jsonb,'worker cancels fulfilled Meta CAPI request');
 END LOOP;
 -- The platform later revokes Meta CAPI.
 UPDATE analytics.organization_policy SET meta_capi_enabled=false WHERE organization=org;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 r:=public.get_unit_meta_capi_approval(un);
 PERFORM assert_eq(r->>'request_state','retry_available','cancelled generation can be retried');
 PERFORM assert_true((r->>'can_request')::boolean,'revoked Meta CAPI is requestable');
 PERFORM public.request_unit_meta_capi_approval(un);
 PERFORM public.request_unit_meta_capi_approval(un);
 PERFORM assert_eq((SELECT revision FROM analytics.organization_meta_capi_request WHERE unit=un),2,'retry creates exactly one new generation');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE unit=un AND workflow_state='pending' AND dedupe_key LIKE '%:2'),2::bigint,'new notifications are deliverable');
 FOREACH state IN ARRAY ARRAY['accepted','sending','unknown'] LOOP
  UPDATE public.email_messages SET workflow_state=state WHERE unit=un AND data->>'request_revision'='2';
  PERFORM assert_false((public.get_unit_meta_capi_approval(un)->>'can_request')::boolean,'accepted or ambiguous notification is not duplicated');
 END LOOP;
 FOREACH state IN ARRAY ARRAY['cancelled','expired','dead','suppressed'] LOOP
  UPDATE public.email_messages SET workflow_state=state WHERE unit=un AND data->>'request_revision'='2';
  PERFORM assert_true((public.get_unit_meta_capi_approval(un)->>'can_request')::boolean,'terminal undelivered notification permits explicit retry');
 END LOOP;
 UPDATE public.email_messages SET workflow_state='pending',expires_at=now()-interval '1 second'
  WHERE unit=un AND data->>'request_revision'='2';
 PERFORM assert_true((public.get_unit_meta_capi_approval(un)->>'can_request')::boolean,'expired queued notification permits retry');
END $$;


-- A delivered notice is fulfilled by a real policy transition.
DO $$
DECLARE x jsonb:=pg_temp.meta_capi_request_fixture(); un bigint:=(x->>'unit')::bigint;
 org bigint:=(x->>'organization')::bigint; spare bigint:=(x->>'spare')::bigint;
BEGIN
 PERFORM public.request_unit_meta_capi_approval(un);
 UPDATE public.email_messages SET workflow_state='accepted' WHERE organization=org AND code='META_CAPI_APPROVAL_REQUEST';
 INSERT INTO analytics.organization_policy(organization,meta_capi_enabled,revision,operator,reason) VALUES(org,true,1,'test','approval');
 UPDATE analytics.organization_policy SET meta_capi_enabled=false WHERE organization=org;
 PERFORM assert_eq(public.get_unit_meta_capi_approval(spare)->>'request_state','retry_available','revoked approval can be requested again even after delivery');
 PERFORM public.request_unit_meta_capi_approval(spare);
 PERFORM assert_eq((SELECT unit FROM analytics.organization_meta_capi_request WHERE organization=org),spare,'new generation records the current requesting Unit');
 PERFORM assert_eq((SELECT revision FROM analytics.organization_meta_capi_request WHERE organization=org),2,'organization generations are monotonic');
END $$;
