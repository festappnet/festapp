-- Transaction-local tenants and emails; the SQL runner rolls everything back.
CREATE FUNCTION pg_temp.measurement_request_fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; other_org bigint; un bigint; spare bigint; manager uuid:=gen_random_uuid();
 admin uuid:=gen_random_uuid(); admin2 uuid:=gen_random_uuid(); no_email uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); editor uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Kulturní platforma','{"DEFAULT_URL":"https://example.invalid/","DEFAULT_LANGUAGE":"en"}') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other platform') RETURNING id INTO other_org;
 INSERT INTO public.units(title,organization) VALUES('Kulturní spolek',org) RETURNING id INTO un;
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
 RETURN jsonb_build_object('organization',org,'otherOrganization',other_org,'unit',un,'spare',spare,
  'manager',manager,'admin',admin,'admin2',admin2,'outsider',outsider,'editor',editor);
END $$;

DO $$
DECLARE x jsonb:=pg_temp.measurement_request_fixture(); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
 r jsonb; m public.email_messages;
BEGIN
 PERFORM assert_eq(public.get_unit_measurement_approval(un),'{"approved":false,"organization_allowed":false,"runtime_supported":false,"requested_at":null,"approved_origins":[],"requested_origins":[],"saved_origins":[],"request_state":"not_requested","can_request":true}'::jsonb,'missing policy and runtime deny approval');
 r:=public.request_unit_measurement_approval(un);
 PERFORM assert_true(r->>'requested_at' IS NOT NULL,'request returns persisted date');
 PERFORM assert_eq((SELECT requested_by FROM analytics.unit_measurement_request WHERE unit=un),(x->>'manager')::uuid,'request records its actor');
 PERFORM assert_eq(public.get_unit_measurement_approval(un),r,'reload reads the persisted status');
 PERFORM assert_eq(public.request_unit_measurement_approval(un),r,'retry returns identical status');
 PERFORM assert_eq((SELECT count(*) FROM analytics.unit_measurement_request WHERE unit=un),1::bigint,'one request per Unit');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND unit=un AND code='MEASUREMENT_APPROVAL_REQUEST'),2::bigint,'every admin with a delivery email receives one notice');
 FOR m IN SELECT * FROM public.email_messages WHERE organization=org AND unit=un AND code='MEASUREMENT_APPROVAL_REQUEST' LOOP
  PERFORM assert_true(m.recipient_user IN ((x->>'admin')::uuid,(x->>'admin2')::uuid),'no manager, editor or other tenant admin receives notice');
  PERFORM assert_eq(m.recipient,public.get_user_delivery_email(m.recipient_user),'canonical delivery email');
  PERFORM assert_eq(m.message_kind,'custom'::text,'existing email queue');
  PERFORM assert_eq(m.dedupe_key,'measurement-approval:'||un||':'||m.recipient_user,'per Unit and admin dedupe');
  PERFORM assert_eq(m.data->>'unit_id',un::text,'Unit id');
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
 END LOOP;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'test','approval');
 r:=public.get_unit_measurement_approval(un);
 PERFORM assert_eq(r->'approved','false'::jsonb,'policy alone is insufficient');
 PERFORM assert_eq(r->'organization_allowed','true'::jsonb,'policy allowed');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,revision,operator,reason)
 VALUES(un,'https://request-'||un||'.pages.dev','gtm-v1',ARRAY['https://example.invalid'],1,'test','approval');
 PERFORM assert_eq(public.get_unit_measurement_approval(un)->'approved','true'::jsonb,'policy and runtime approve');
 SELECT * INTO m FROM public.email_messages WHERE organization=org AND unit=un AND code='MEASUREMENT_APPROVAL_REQUEST' LIMIT 1;
 PERFORM assert_false(public.email_intent_valid(m),'already approved request mail is obsolete');
 PERFORM public.request_unit_measurement_approval(un);
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND code='MEASUREMENT_APPROVAL_REQUEST'),2::bigint,'approval and retries send no more mail');
 UPDATE analytics.organization_policy SET enabled=false WHERE organization=org;
 PERFORM assert_eq(public.get_unit_measurement_approval(un)->'approved','false'::jsonb,'runtime alone is insufficient');
 PERFORM assert_eq(public.get_unit_measurement_approval(un)->'requested_at',r->'requested_at','request survives policy changes');
 PERFORM public.delete_unit(un);
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.unit_measurement_request WHERE unit=un),'Unit deletion cascades request');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org AND code='MEASUREMENT_APPROVAL_REQUEST' AND unit IS NULL AND workflow_state='cancelled'),2::bigint,'deletion cancels queued requests and detaches Unit');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.measurement_request_fixture(); un bigint:=(x->>'unit')::bigint; actor text; role_name text; op text;
BEGIN
 FOR actor IN SELECT unnest(ARRAY[x->>'outsider',x->>'editor','']) LOOP
  PERFORM set_config('request.jwt.claim.sub',actor,true);
  BEGIN PERFORM public.request_unit_measurement_approval(un); RAISE EXCEPTION 'unauthorized request'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 FOR actor IN SELECT unnest(ARRAY[x->>'outsider','']) LOOP
  PERFORM set_config('request.jwt.claim.sub',actor,true);
  BEGIN PERFORM public.get_unit_measurement_approval(un); RAISE EXCEPTION 'unauthorized read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',x->>'editor',true);
 PERFORM assert_true(public.get_unit_measurement_approval(un) IS NOT NULL,'Unit editor can read status');
 PERFORM set_config('request.jwt.claim.sub',x->>'manager',true);
 PERFORM public.request_unit_measurement_approval(un);
 UPDATE public.unit_users SET is_manager=false WHERE unit=un AND "user"=(x->>'manager')::uuid;
 BEGIN PERFORM public.request_unit_measurement_approval(un); RAISE EXCEPTION 'unauthorized replay'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  FOREACH op IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   PERFORM assert_false(has_table_privilege(role_name,'analytics.unit_measurement_request',op),'no direct request table access');
  END LOOP;
  PERFORM assert_false(has_function_privilege(role_name,'public.unit_measurement_approval_internal(bigint)','EXECUTE'),'internal status is private');
  PERFORM assert_eq(has_function_privilege(role_name,'public.request_unit_measurement_approval(bigint)','EXECUTE'),role_name='authenticated','request RPC is authenticated only');
  PERFORM assert_eq(has_function_privilege(role_name,'public.get_unit_measurement_approval(bigint)','EXECUTE'),role_name='authenticated','read RPC is authenticated only');
 END LOOP;
 PERFORM assert_true((SELECT relrowsecurity FROM pg_class WHERE oid='analytics.unit_measurement_request'::regclass),'request table has RLS');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.measurement_request_fixture(); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint; oc bigint; bank bigint;
BEGIN
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'test','approved before request');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,revision,operator,reason)
 VALUES(un,'https://approved-'||un||'.pages.dev','gtm-v1',ARRAY['https://example.invalid'],1,'test','approved before request');
 PERFORM assert_eq(public.request_unit_measurement_approval(un)->'approved','true'::jsonb,'already approved is a no-op');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.unit_measurement_request WHERE unit=un),'approved Unit creates no request');
 DELETE FROM analytics.unit_runtime WHERE unit=un;
 UPDATE public.organizations SET data='{"DEFAULT_URL":"http://example.invalid"}' WHERE id=org;
 BEGIN PERFORM public.request_unit_measurement_approval(un); RAISE EXCEPTION 'unsafe origin accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'measurement_notification_origin_missing' THEN RAISE; END IF; END;
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.unit_measurement_request WHERE unit=un),'failure leaves request retryable');
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time)
 VALUES('Demo request',un,org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Demo request','CASH') RETURNING id INTO bank;
 INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,sort_order,description,reference_at)
 VALUES(oc,org,'ball','measurement-request-test',bank,0,'Synthetic',now());
 PERFORM assert_true(public.is_demo_unit(un),'demo fixture');
 UPDATE public.unit_users SET is_editor_view=true WHERE unit=un AND "user"=(x->>'manager')::uuid;
 PERFORM public.request_unit_measurement_approval(un);
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.unit_measurement_request WHERE unit=un),'demo Unit creates no request');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages WHERE organization=org AND code='MEASUREMENT_APPROVAL_REQUEST'),'approved and demo no-ops send no mail');
 PERFORM set_config('request.jwt.claim.sub',x->>'outsider',true);
 BEGIN PERFORM public.request_unit_measurement_approval(un); RAISE EXCEPTION 'unauthorized demo request'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

DO $$
DECLARE x jsonb:=pg_temp.measurement_request_fixture(); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
BEGIN
 -- Only an admin without a delivery e-mail remains: nobody can be notified.
 UPDATE public.organization_users SET is_admin=false WHERE organization=org AND "user" IN ((x->>'admin')::uuid,(x->>'admin2')::uuid);
 BEGIN PERFORM public.request_unit_measurement_approval(un); RAISE EXCEPTION 'request without recipient accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'measurement_request_no_recipient' THEN RAISE; END IF; END;
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM analytics.unit_measurement_request WHERE unit=un),'no recipient leaves the request retryable');
 UPDATE public.organization_users SET is_admin=true WHERE organization=org AND "user"=(x->>'admin')::uuid;
 PERFORM assert_true(public.request_unit_measurement_approval(un)->>'requested_at' IS NOT NULL,'request succeeds once an admin can be notified');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.measurement_request_fixture(); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
 r jsonb; m public.email_messages; bad jsonb;
BEGIN
 FOREACH bad IN ARRAY ARRAY['["http://example.com"]'::jsonb,'["https://example.com/path"]'::jsonb,
  '["https://example.com/"]'::jsonb,'["https://user@example.com"]'::jsonb,'["https://example.com?x"]'::jsonb,
  '["https://example.com#x"]'::jsonb,'["https://example.com:65536"]'::jsonb,'[7]'::jsonb,
  (SELECT jsonb_agg('https://site'||i||'.example') FROM generate_series(1,11) i)] LOOP
  BEGIN
   PERFORM public.merge_configuration_settings_internal_v1('{}',jsonb_build_object('measurement_websites',bad),'unit');
   RAISE EXCEPTION 'invalid website accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 UPDATE public.units SET data=public.merge_configuration_settings_internal_v1(data,
  '{"measurement_websites":["https://example.invalid","https://www.example.invalid:443"]}','unit') WHERE id=un;
 r:=public.request_unit_measurement_approval(un);
 PERFORM assert_eq(r->'approved_origins','[]'::jsonb,'proposals grant no approval');
 PERFORM assert_eq(r->'requested_origins','["https://example.invalid","https://www.example.invalid:443"]'::jsonb,'request snapshots websites');
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'test','approval');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,revision,operator,reason)
 VALUES(un,'https://request-'||un||'.pages.dev','gtm-v1',ARRAY['https://example.invalid'],1,'test','approval');
 SELECT * INTO m FROM public.email_messages WHERE unit=un AND code='MEASUREMENT_APPROVAL_REQUEST' LIMIT 1;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_true(public.email_intent_valid(m),'pending origin keeps mail valid after runtime approval');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 UPDATE public.units SET data=jsonb_set(data,'{measurement_websites}',data->'measurement_websites'||'"https://new.example.invalid"'::jsonb) WHERE id=un;
 r:=public.request_unit_measurement_approval(un);
 PERFORM assert_eq((SELECT revision FROM analytics.unit_measurement_request WHERE unit=un),2,'new website creates another request after approval');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_false(public.email_intent_valid(m),'superseded mail is obsolete');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_eq(r->'approved_origins','["https://example.invalid"]'::jsonb,'new request does not approve websites');
 PERFORM public.request_unit_measurement_approval(un);
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE unit=un AND code='MEASUREMENT_APPROVAL_REQUEST'),4::bigint,'repeat request is idempotent');
 SELECT * INTO m FROM public.email_messages WHERE unit=un AND code='MEASUREMENT_APPROVAL_REQUEST' AND data->>'request_revision'='2' LIMIT 1;
 PERFORM assert_eq(m.data->'proposed_websites',r->'requested_origins','email carries all proposals');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_true(public.email_intent_valid(m),'new request is deliverable after runtime approval');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 UPDATE analytics.unit_runtime SET parent_origins=ARRAY['https://example.invalid','https://www.example.invalid:443','https://new.example.invalid'] WHERE unit=un;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_false(public.email_intent_valid(m),'platform approval obsoletes request');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
END $$;

-- A historical snapshot is not an active request after worker cancellation.
DO $$
DECLARE x jsonb:=pg_temp.measurement_request_fixture(); un bigint:=(x->>'unit')::bigint;
 org bigint:=(x->>'organization')::bigint; r jsonb; state text; claimed jsonb;
BEGIN
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES(org,true,1,'test','approval');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,revision,operator,reason)
 VALUES(un,'https://lifecycle-'||un||'.pages.dev','gtm-v1',ARRAY['https://approved.example'],1,'test','approval');
 UPDATE public.units SET data=jsonb_set(coalesce(data,'{}'),'{measurement_websites}','["https://pending.example"]') WHERE id=un;
 r:=public.get_unit_measurement_approval(un);
 PERFORM assert_eq(r->>'request_state','not_requested','new proposal is not requested');
 PERFORM assert_true((r->>'can_request')::boolean,'new proposal can be requested');
 PERFORM public.request_unit_measurement_approval(un);
 PERFORM public.request_unit_measurement_approval(un);
 PERFORM assert_eq((SELECT revision FROM analytics.unit_measurement_request WHERE unit=un),1,'active retries are idempotent');
 UPDATE public.units SET data=jsonb_set(data,'{measurement_websites}','[]') WHERE id=un;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 -- Defer other transaction-local fixtures; exercise the real worker boundary.
 UPDATE public.email_messages SET target_time='infinity' WHERE unit IS DISTINCT FROM un;
 UPDATE public.email_capacity SET paused=false,quota_at=now(),circuit_until=NULL,max_preparing=2,worker_url=NULL;
 FOR i IN 1..2 LOOP
  claimed:=public.claim_email();
  PERFORM assert_eq(claimed,'{"skipped":true}'::jsonb,'worker cancels withdrawn request');
 END LOOP;
 UPDATE public.units SET data=jsonb_set(data,'{measurement_websites}','["https://pending.example"]') WHERE id=un;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 r:=public.get_unit_measurement_approval(un);
 PERFORM assert_eq(r->>'request_state','retry_available','cancelled generation can be retried');
 PERFORM assert_true((r->>'can_request')::boolean,'re-added website is requestable');
 PERFORM public.request_unit_measurement_approval(un);
 PERFORM public.request_unit_measurement_approval(un);
 PERFORM assert_eq((SELECT revision FROM analytics.unit_measurement_request WHERE unit=un),2,'retry creates exactly one new generation');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE unit=un AND workflow_state='pending'),2::bigint,'new notifications are deliverable');
 FOREACH state IN ARRAY ARRAY['accepted','sending','unknown'] LOOP
  UPDATE public.email_messages SET workflow_state=state WHERE unit=un AND data->>'request_revision'='2';
  PERFORM assert_false((public.get_unit_measurement_approval(un)->>'can_request')::boolean,'accepted or ambiguous notification is not duplicated');
 END LOOP;
 FOREACH state IN ARRAY ARRAY['cancelled','expired','dead','suppressed'] LOOP
  UPDATE public.email_messages SET workflow_state=state WHERE unit=un AND data->>'request_revision'='2';
  PERFORM assert_true((public.get_unit_measurement_approval(un)->>'can_request')::boolean,'terminal undelivered notification permits explicit retry');
 END LOOP;
 UPDATE public.email_messages SET workflow_state='pending',expires_at=now()-interval '1 second'
  WHERE unit=un AND data->>'request_revision'='2';
 PERFORM assert_true((public.get_unit_measurement_approval(un)->>'can_request')::boolean,'expired queued notification permits retry');
END $$;
