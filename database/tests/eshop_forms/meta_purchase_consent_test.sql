-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint;
 org bigint:=(x->>'organization')::bigint; snapshot jsonb; b analytics.website_consent_bindings; bad jsonb;
BEGIN
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=org;
 UPDATE public.units SET data=data||'{"measurement_consent_bridge":true,"measurement_websites":["https://tickets.example"]}' WHERE id=un;
 INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled)
 VALUES(un,'123456',gen_random_uuid(),'https://tickets.example',true);
 snapshot:=jsonb_build_object('source','klaro','capturedAt',to_char((clock_timestamp()-interval '1 second') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal(un)->>'consentRevision',
  'ad_storage',true,'ad_user_data',true,'ad_personalization',true);
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot),'scoped saved standalone choice');
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot-'source') IS FALSE,'missing source returns false, never SQL NULL');
 UPDATE public.organizations SET data=data-'DEFAULT_URL' WHERE id=org;
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot) IS FALSE,'missing standalone service URL returns false, never SQL NULL');
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=org;
 FOREACH bad IN ARRAY ARRAY['null'::jsonb,'{}'::jsonb,snapshot||'{"ad_user_data":false}',snapshot||'{"ad_personalization":false}',
  snapshot||'{"ad_storage":false}',snapshot||'{"source":"invented"}',
  snapshot||'{"consentRevision":"obsolete"}',snapshot||'{"websiteOrigin":"https://attacker.example"}'] LOOP
  PERFORM assert_false(public.meta_purchase_snapshot_valid_internal(un,bad),'malformed, denied, stale or unbound choice fails closed');
 END LOOP;
 INSERT INTO analytics.website_consent_bindings(unit,website_origin,platform,provider_config,version,enabled,confirmed_revision,confirmed_at)
 VALUES(un,'https://tickets.example','html','{"provider":"cookiebot"}',1,true,snapshot->>'consentRevision',clock_timestamp()-interval '1 minute') RETURNING * INTO b;
 snapshot:=snapshot||jsonb_build_object('source','cookiebot','binding',jsonb_build_object('id',b.id,'version',b.version));
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot),'managed choice uses live exact binding');
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot||'{"decidedAt":"2000-01-01T00:00:00.000Z"}'),'decision before binding confirmation is accepted');
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot||'{"decidedAt":"invalid"}'),'invalid optional audit date does not invalidate consent');
 UPDATE analytics.website_consent_bindings SET provider_config='{"provider":"complianz","policyId":"42"}' WHERE id=b.id;
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot||'{"source":"complianz"}'),'Complianz current grant without decision time');
 UPDATE analytics.website_consent_bindings SET provider_config='{"provider":"cookiebot"}' WHERE id=b.id;

 -- Durable snapshot remains valid after the live transport permission expires.
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot||'{"transportExpiresAt":1}'),'transport expiry does not expire captured order consent');
 UPDATE analytics.website_consent_bindings SET version=2 WHERE id=b.id;
 PERFORM assert_false(public.meta_purchase_snapshot_valid_internal(un,snapshot),'changed binding blocks pending sends');
 UPDATE analytics.website_consent_bindings SET version=1,enabled=false WHERE id=b.id;
 PERFORM assert_false(public.meta_purchase_snapshot_valid_internal(un,snapshot),'disconnected binding blocks pending sends');
 UPDATE analytics.website_consent_bindings SET enabled=true WHERE id=b.id;
 UPDATE analytics.meta_purchase_connectors SET enabled=false WHERE unit=un;
 PERFORM assert_false(public.meta_purchase_snapshot_valid_internal(un,snapshot),'disabled connector blocks pending sends');
END $$;

DO $$
<<review>>
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint; fid bigint:=(x->>'form')::bigint;
 snapshot jsonb; checkout jsonb; receipt jsonb; replay jsonb; oid bigint; b analytics.website_consent_bindings; claimed uuid:=gen_random_uuid();
 command_id uuid:=gen_random_uuid(); client_id uuid:=gen_random_uuid();
 bad jsonb; other_command uuid:=gen_random_uuid(); other_order bigint; changed_checkout jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=(x->>'organization')::bigint;
 UPDATE public.units SET data=data||'{"measurement_consent_bridge":true,"measurement_websites":["https://tickets.example"]}' WHERE id=un;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES((x->>'organization')::bigint,true,1,'fixture','saved CMP consent');
 UPDATE public.forms SET is_open=true,data=data||'{"analytics":{"enabled":true}}' WHERE id=fid;
 PERFORM public.reserve_public_link_internal('form',fid,x->>'link',true);
 INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled)
 VALUES(un,'123456',gen_random_uuid(),'https://tickets.example',true);
 INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES(fid,un);
 PERFORM assert_true(public.get_meta_purchase_consent(x->>'link') IS NULL,'no public collection notice before retention runs');
 PERFORM public.purge_meta_purchase_data_internal();
 INSERT INTO analytics.website_consent_bindings(unit,website_origin,platform,provider_config,version,enabled,confirmed_revision,confirmed_at)
 VALUES(un,'https://tickets.example','html','{"provider":"cookiebot"}',1,true,
  public.unit_measurement_consent_scope_internal(un)->>'consentRevision',clock_timestamp()-interval '1 minute') RETURNING * INTO b;
 snapshot:=jsonb_build_object('source','cookiebot','capturedAt',to_char((clock_timestamp()-interval '1 second') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal(un)->>'consentRevision',
  'revision',public.get_meta_purchase_consent(x->>'link')->>'revision','userAgent','Consent regression',
  'ad_storage',true,'ad_user_data',true,'ad_personalization',true,
  'transportExpiresAt',floor(extract(epoch FROM clock_timestamp())*1000)+59000,
  'binding',jsonb_build_object('id',b.id,'version',b.version,'untrustedContact','must not persist'),
  'untrustedContact','must not persist',
  'matching',jsonb_build_object('fbp','fb.1.1795000000000.1234','fbc','fb.1.1795000000000.Click_123'));
 PERFORM set_config('request.headers','{"x-festapp-client-ip":"2001:db8::1"}',true);
 checkout:=pg_temp.checkout(x)||jsonb_build_object('metaPurchaseConsent',snapshot);
 receipt:=public.create_ticket_order_client_sync_v1(checkout,command_id,client_id);
 PERFORM assert_eq(receipt#>>'{data,code}','200','snapshot does not affect checkout');
 oid:=(receipt#>>'{data,order,id}')::bigint;
 PERFORM assert_true(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'valid connected CMP captured');
 PERFORM assert_true((SELECT consent_snapshot ? 'capturedAt' AND NOT consent_snapshot ? 'decidedAt'
   AND (consent_snapshot->>'capturedAt')::timestamptz >= transaction_timestamp()
   FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'server records capture time without requiring decision metadata');

 PERFORM assert_eq((SELECT fbp FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'fb.1.1795000000000.1234','matching is captured with this exact order');
 PERFORM assert_eq((SELECT host(client_ip) FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'2001:db8::1','trusted checkout header supplies the address');
 PERFORM assert_false(receipt::text LIKE '%fb.1.%' OR receipt::text LIKE '%2001:db8%','matching never enters the browser receipt');
 replay:=public.create_ticket_order_client_sync_v1(
  jsonb_set(checkout,'{metaPurchaseConsent,matching,fbc}','"fb.1.1795000001000.Click_123"'),command_id,client_id);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'reload with changed matching replays the first order');
 replay:=public.create_ticket_order_client_sync_v1(checkout-'metaPurchaseConsent',command_id,client_id);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'checkout without the original consent returns the original order');
 replay:=public.create_ticket_order_client_sync_v1(
  jsonb_set(checkout,'{metaPurchaseConsent,ad_storage}','false'),command_id,client_id);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'changed consent returns the original order');
 BEGIN
  PERFORM public.create_ticket_order_client_sync_v1(checkout||'{"email":"other-buyer@example.invalid"}',command_id,client_id);
  RAISE EXCEPTION 'different business data cannot replay a command';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 BEGIN
  PERFORM public.create_ticket_order_client_sync_v1(checkout-'metaPurchaseConsent',command_id,gen_random_uuid());
  RAISE EXCEPTION 'a different buyer cannot replay the receipt';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 -- Previous receipts stored the complete consent decision in the request hash.
 UPDATE public.client_mutation_receipts SET request_sha256=encode(extensions.digest(convert_to(jsonb_build_object(
  'occasion',(x->>'occasion')::bigint,'order',public.strip_payment_sources_internal(checkout)#-'{metaPurchaseConsent,matching}')::text,'UTF8'),'sha256'),'hex')
 WHERE client_mutation_receipts.command_id=review.command_id;
 replay:=public.create_ticket_order_client_sync_v1(checkout,command_id,client_id);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'exact historical decision still recovers its original order');

 changed_checkout:=(checkout-'metaPurchaseConsent')||'{"email":"unconsented@example.invalid"}';
 replay:=public.create_ticket_order_client_sync_v1(changed_checkout,other_command,client_id);
 PERFORM assert_eq(replay#>>'{data,code}','200','checkout without consent succeeds');
 other_order:=(replay#>>'{data,order,id}')::bigint;
 replay:=public.create_ticket_order_client_sync_v1(changed_checkout||jsonb_build_object('metaPurchaseConsent',snapshot),other_command,client_id);
 PERFORM assert_eq(replay#>>'{data,order,id}',other_order::text,'new consent still recovers the originally unconsented order');
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=other_order),
  'a replay does not add consent to an already committed order');
 PERFORM assert_eq((SELECT fbc FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
  'fb.1.1795000000000.Click_123','replaying a checkout never rewrites original Meta matching');
 UPDATE analytics.meta_purchase_deliveries SET consent_at=clock_timestamp()-interval '8 days' WHERE order_id=oid;
 -- Delivery is disabled; PostgreSQL retention still runs.
 UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp() WHERE unit=un;
 PERFORM assert_true(public.get_meta_purchase_consent(x->>'link') IS NULL,'paused delivery cannot authorize checkout matching');
 PERFORM public.purge_meta_purchase_data_internal();
 UPDATE analytics.meta_purchase_connectors SET paused_at=NULL WHERE unit=un;
 PERFORM assert_true((SELECT client_ip IS NULL AND fbp IS NOT NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'seven-day IP cleanup also covers unpaid orders and retains younger matching');
 UPDATE analytics.meta_purchase_deliveries SET consent_at=clock_timestamp() WHERE order_id=oid;
 PERFORM assert_false((SELECT consent_snapshot ? 'untrustedContact' OR consent_snapshot->'binding' ? 'untrustedContact'
  FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'only allowlisted consent fields persist');
 DELETE FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
 UPDATE analytics.meta_purchase_retention_state SET last_sweep=clock_timestamp()-interval '11 minutes';
 PERFORM assert_true(public.get_meta_purchase_consent(x->>'link') IS NULL,'stale retention closes the public notice');
 PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot);
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'stale retention prevents new collection');
 PERFORM public.purge_meta_purchase_data_internal();
 PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot||'{"ad_storage":false}');
 PERFORM public.capture_meta_purchase_consent_internal(oid,jsonb_set(snapshot,'{binding,version}','2'));
 PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot||'{"websiteOrigin":"https://other.example"}');
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'denied, foreign-origin and foreign-binding matching cannot persist');
 PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot-'source');
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'missing source cannot capture');
 UPDATE public.organizations SET data=data-'DEFAULT_URL' WHERE id=(x->>'organization')::bigint;
 PERFORM public.capture_meta_purchase_consent_internal(oid,(snapshot-'binding')||'{"source":"klaro"}');
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'missing service URL cannot capture');
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=(x->>'organization')::bigint;
 FOREACH bad IN ARRAY ARRAY[snapshot-'capturedAt',snapshot||'{"capturedAt":"invalid"}'] LOOP
  PERFORM public.capture_meta_purchase_consent_internal(oid,bad);
  PERFORM assert_true((SELECT (consent_snapshot->>'capturedAt')::timestamptz>=transaction_timestamp() FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'client capture metadata never gates server capture');
  DELETE FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[snapshot||'{"decidedAt":"2020-01-01T00:00:00.000Z"}',
  (snapshot-'capturedAt')||'{"timestamp":"2020-01-01T00:00:00.000Z"}'] LOOP
  PERFORM public.capture_meta_purchase_consent_internal(oid,bad);
  PERFORM assert_true((SELECT consent_decided_at=coalesce(bad->>'decidedAt',bad->>'timestamp')::timestamptz
   FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'valid current and legacy decision dates are audit metadata');
  DELETE FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[snapshot||'{"decidedAt":"invalid"}',snapshot||'{"decidedAt":"2099-01-01T00:00:00.000Z"}'] LOOP
  PERFORM public.capture_meta_purchase_consent_internal(oid,bad);
  PERFORM assert_true((SELECT consent_decided_at IS NULL AND NOT consent_snapshot ? 'decidedAt'
   FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'malformed and future dates are omitted without blocking capture');
  DELETE FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
 END LOOP;
 PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot);
 -- A snapshot captured on a live bridge stays durable after its lease expires.
 UPDATE analytics.meta_purchase_deliveries SET phone_hash=repeat('b',64),lease=claimed,lease_until=clock_timestamp()+interval '1 minute' WHERE order_id=oid;
 UPDATE analytics.website_consent_bindings SET version=2 WHERE id=b.id;
 PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'live binding change stops a claimed pending send');
 PERFORM assert_true((SELECT status='invalid' AND consent_snapshot IS NULL AND email_hash IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL
  FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'invalid delivery erases visitor metadata');
 UPDATE analytics.meta_purchase_deliveries SET status='pending',consent_snapshot=snapshot,
  phone_hash=repeat('b',64),fbp='fb.1.1795000000000.1234',fbc='fb.1.1795000000000.Click_123',client_ip='192.0.2.1',consent_at=clock_timestamp()-interval '31 days',done_at=NULL WHERE order_id=oid;
 PERFORM public.purge_meta_purchase_data_internal();
 PERFORM assert_true((SELECT status='expired' AND error_code='retention_expired' AND consent_snapshot IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'retention expiry erases snapshot');
 UPDATE analytics.meta_purchase_deliveries SET phone_hash=repeat('b',64),fbp='fb.1.1795000000000.1234',fbc='fb.1.1795000000000.Click_123',client_ip='192.0.2.1',status='pending',consent_snapshot=snapshot,lease=claimed,prepared=true WHERE order_id=oid;
 PERFORM assert_true(public.finish_meta_purchase_delivery(oid,claimed,'sent'),'receipt is finalized');
 PERFORM assert_true((SELECT status='sent' AND consent_snapshot IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'sent receipts contain no snapshot');
 -- Meta accepted a test event without an active Test Events session: sent, with an explanatory code.
 UPDATE analytics.meta_purchase_deliveries SET status='pending',consent_snapshot=snapshot,phone_hash=repeat('b',64),
  fbp='fb.1.1795000000000.1234',lease=claimed,prepared=true,done_at=NULL WHERE order_id=oid;
 PERFORM assert_true(public.finish_meta_purchase_delivery(oid,claimed,'sent_test_inactive'),'inactive test session receipt is finalized');
 PERFORM assert_true((SELECT status='sent' AND error_code='test_events_inactive' AND done_at IS NOT NULL AND consent_snapshot IS NULL
  AND email_hash IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL AND client_agent IS NULL
  AND source_url IS NULL AND lease IS NULL AND lease_until IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
  'inactive test session is a scrubbed sent receipt with its notice');
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES((x->>'organization')::bigint,(x->>'actor')::uuid,true);
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 UPDATE analytics.meta_purchase_connectors SET test_event_code='TEST123' WHERE unit=un;
 PERFORM assert_true(public.get_unit_meta_purchase(un)#>>'{test_events_notice,at}' IS NOT NULL,'settings explain the missing Test Events receipt');
 PERFORM assert_true(public.get_unit_meta_purchase(un)#>>'{last_error,code}' IS DISTINCT FROM 'test_events_inactive','accepted receipt is separate from failures');
 INSERT INTO analytics.meta_purchase_deliveries(order_id,unit,connector_revision,consent_revision,status,error_code,done_at)
 SELECT other_order,un,connector_revision,consent_revision,'failed','rejected',done_at+interval '1 second'
 FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
 PERFORM assert_eq(public.get_unit_meta_purchase(un)#>>'{last_error,code}','rejected','delivery failures remain visible');
 PERFORM assert_true(public.get_unit_meta_purchase(un)#>>'{test_events_notice,at}' IS NOT NULL,'a later failure does not replace the accepted notice');
 UPDATE analytics.meta_purchase_deliveries SET status='sent',error_code=NULL WHERE order_id=other_order;
 PERFORM assert_true(public.get_unit_meta_purchase(un)#>>'{test_events_notice,at}' IS NULL,'a newer successful receipt with the same code clears the notice');
 DELETE FROM analytics.meta_purchase_deliveries WHERE order_id=other_order;
 UPDATE analytics.meta_purchase_connectors SET revision=gen_random_uuid() WHERE unit=un;
 PERFORM assert_true(public.get_unit_meta_purchase(un)#>>'{test_events_notice,at}' IS NULL,'a new connector revision clears the notice');
 UPDATE analytics.meta_purchase_connectors SET test_event_code=NULL,revision=(SELECT connector_revision FROM analytics.meta_purchase_deliveries WHERE order_id=oid) WHERE unit=un;
 DELETE FROM public.organization_users WHERE organization=(x->>'organization')::bigint AND "user"=(x->>'actor')::uuid;
 PERFORM set_config('request.jwt.claim.sub','',true);
 UPDATE analytics.meta_purchase_deliveries SET error_code=NULL WHERE order_id=oid;
 PERFORM public.issue_order_overview_internal(oid,pg_temp.delivery('fixture',repeat('c',64),oid),gen_random_uuid());
 UPDATE analytics.meta_purchase_deliveries SET consent_at=clock_timestamp(),consent_decided_at='2020-01-01T00:00:00Z' WHERE order_id=oid;
 PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot||'{"ad_storage":false,"decidedAt":"2000-01-01T00:00:00.000Z"}'),
  'a provably older CMP refusal cannot withdraw');
 UPDATE analytics.meta_purchase_deliveries SET consent_decided_at='2099-01-01T00:00:00Z',
  done_at=clock_timestamp()-interval '35 days' WHERE order_id=oid;
 PERFORM assert_true(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot||'{"ad_storage":false,"decidedAt":"2020-01-02T00:00:00.000Z"}'),
  'an old future-dated grant cannot veto a current refusal');
 PERFORM assert_true((SELECT status='sent' AND done_at<statement_timestamp()-interval '30 days'
  FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'withdrawal does not move a completed outcome into the current reporting window');
 UPDATE analytics.meta_purchase_deliveries SET revoked_at=NULL WHERE order_id=oid;
 PERFORM pg_sleep(0.002);
 snapshot:=snapshot||jsonb_build_object('capturedAt',to_char((clock_timestamp()) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'ad_storage',false);
 PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot||'{"websiteOrigin":"https://other.example"}'),
  'another website cannot withdraw captured consent');
 PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot||'{"ad_storage":null}'),
  'an unknown purpose cannot withdraw captured consent');
 FOREACH bad IN ARRAY ARRAY[snapshot||'{"source":"complianz"}',snapshot||'{"consentRevision":"obsolete"}',jsonb_set(snapshot,'{binding,version}','2')] LOOP
  PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('c',64),oid,bad),'foreign source, revision or binding cannot withdraw');
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[snapshot||'{"capturedAt":"2000-01-01T00:00:00.000Z"}',snapshot||'{"capturedAt":"2099-01-01T00:00:00.000Z"}'] LOOP
  PERFORM assert_true(public.revoke_meta_purchase_consent(repeat('c',64),oid,bad),'current refusal ignores client clock offset');
  UPDATE analytics.meta_purchase_deliveries SET revoked_at=NULL WHERE order_id=oid;
 END LOOP;
 PERFORM assert_true(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot),
  'a current refusal without a decision date withdraws even after the snapshot was scrubbed');
 PERFORM assert_true((SELECT status='sent' AND revoked_at IS NOT NULL AND consent_snapshot IS NULL
  FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'withdrawal closes later Meta companion eligibility');
 UPDATE analytics.meta_purchase_deliveries SET phone_hash=repeat('b',64),fbp='fb.1.1795000000000.1234',fbc='fb.1.1795000000000.Click_123',client_ip='192.0.2.1',status='pending',consent_snapshot=snapshot,revoked_at=NULL WHERE order_id=oid;
 PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('d',64),oid),'order id without buyer capability cannot revoke');
 PERFORM assert_true(public.revoke_meta_purchase_consent(repeat('c',64),oid),'buyer capability withdraws captured consent');
 PERFORM assert_true((SELECT status='revoked' AND consent_snapshot IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'withdrawal erases snapshot');
END $$;

-- Later CAPI enablement cannot send a second Purchase for an immutable
-- order-time cohort, even when a captured delivery and fully-paid fact exist.
DO $$
DECLARE x jsonb; un bigint; fid bigint;
 mode text; email_event jsonb; email_connection bigint; email_bank bigint; email_receipt jsonb; receipt jsonb; oid bigint; snapshot jsonb; payment_id bigint; transaction_id bigint;
 paid_event uuid; order_event uuid; claimed uuid; prepared jsonb; order_data jsonb; reason_case text; expected_reason text; baseline analytics.meta_purchase_deliveries; paid_at timestamptz; overview jsonb;
BEGIN
 FOREACH mode IN ARRAY ARRAY['order','legacy','missing','paid_without_capi','legacy_capi_flag','paid','no_browser_items','waitlist_acceptance','confirmed_email'] LOOP
  x:=pg_temp.fixture(NULL);un:=(x->>'unit')::bigint;fid:=(x->>'form')::bigint;
 PERFORM set_config('request.jwt.claim.sub','',true);
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=(x->>'organization')::bigint;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES((x->>'organization')::bigint,true,1,'fixture','immutable purchase cohort');
 UPDATE public.forms SET is_open=true,data=data||'{"analytics":{"enabled":true,"purchase_timing":"order"}}' WHERE id=fid;
 PERFORM public.reserve_public_link_internal('form',fid,x->>'link',true);
 INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled)
 VALUES(un,'123456',vault.create_secret(repeat('t',40),'consent-cohort-'||un),'https://tickets.example',false);
 INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES(fid,un);
  -- Only the final order retains an original CAPI-required flag. A paid-only
  -- browser order created before enablement must also remain excluded.
  UPDATE public.forms SET data=jsonb_set(data,'{analytics,purchase_timing}',
   to_jsonb(CASE WHEN mode='paid_without_capi' THEN 'paid'::text ELSE 'order'::text END)) WHERE id=fid;
  UPDATE analytics.meta_purchase_connectors SET enabled=(mode IN ('paid','legacy_capi_flag','no_browser_items','waitlist_acceptance','confirmed_email')) WHERE unit=un;
  receipt:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||jsonb_build_object('email','consent-'||mode||'-'||un::text||'@example.invalid'),gen_random_uuid(),gen_random_uuid());
  PERFORM assert_eq(receipt#>>'{data,code}','200','cohort fixture checkout succeeds');
  oid:=(receipt#>>'{data,order,id}')::bigint;
  IF mode IN ('no_browser_items','waitlist_acceptance') THEN
   DELETE FROM analytics.conversion_facts WHERE "order"=oid AND kind='purchase';
   IF mode='no_browser_items' THEN
    SELECT data INTO order_data FROM eshop.orders WHERE id=oid;
    UPDATE eshop.orders SET data=jsonb_set(data,'{tickets}','[]'::jsonb) WHERE id=oid;
    PERFORM public.publish_form_measurement_event_internal('checkout_finalized',oid);
    UPDATE eshop.orders SET data=order_data WHERE id=oid;
    PERFORM assert_true(public.form_purchase_datalayer_internal(oid) IS NULL,'no browser item payload is exported');
   ELSE
    PERFORM public.publish_form_measurement_event_internal('waitlist_offer_accepted',oid);
    PERFORM assert_eq(public.form_order_purchase_timing_internal(oid),'paid','offer timing follows its form');
   END IF;
  END IF;
  SELECT event_id INTO STRICT order_event FROM analytics.conversion_facts WHERE "order"=oid AND kind='purchase';
  IF mode='legacy' THEN
   UPDATE analytics.conversion_facts SET payload=payload-'purchase_timing' WHERE "order"=oid AND kind='purchase';
  ELSIF mode='legacy_capi_flag' THEN
   UPDATE analytics.conversion_facts SET payload=payload-'capi_required' WHERE "order"=oid AND kind='purchase';
  ELSIF mode='missing' THEN
   DELETE FROM analytics.conversion_facts WHERE "order"=oid AND kind='purchase';
  END IF;
  UPDATE analytics.meta_purchase_connectors SET enabled=true WHERE unit=un;
  PERFORM assert_eq((SELECT purchase_timing FROM public.form_measurement_decision_internal(fid)),'paid','current CAPI setting requests paid');
  IF mode IN ('order','legacy') THEN
   PERFORM assert_eq(public.form_order_purchase_timing_internal(oid),'order','old order cohort remains order after enablement');
  ELSIF mode='paid_without_capi' THEN
   PERFORM assert_eq(public.form_order_purchase_timing_internal(oid),'paid','paid-only browser cohort is frozen before CAPI enablement');
  ELSIF mode='missing' THEN
   PERFORM assert_true(public.form_order_purchase_timing_internal(oid) IS NULL,'missing snapshot confers no paid cohort');
  END IF;
  PERFORM assert_true(public.form_order_purchase_capi_required_internal(oid) IS NOT DISTINCT FROM (mode IN ('paid','no_browser_items','confirmed_email')),
   'CAPI is required only when frozen at creation, missing flag fails closed');
  snapshot:=jsonb_build_object('source','klaro','capturedAt',to_char((clock_timestamp()-interval '1 second') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal(un)->>'consentRevision',
   'revision',public.get_meta_purchase_consent(x->>'link')->>'revision','userAgent','Cohort regression',
   'ad_storage',true,'ad_user_data',true,'ad_personalization',true);
  UPDATE eshop.orders SET data=data||'{"phone":"+420 777 123 456"}' WHERE id=oid;
  PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot||'{"matching":{"fbp":"fb.1.1795000000000.1234","fbc":"invalid"}}');
  PERFORM assert_eq((SELECT phone_hash FROM analytics.meta_purchase_deliveries WHERE order_id=oid),encode(extensions.digest('420777123456','sha256'),'hex'),'hash uses country code and digits only');
  PERFORM assert_true(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'captured pending delivery exists before payment');
  SELECT payment_info INTO STRICT payment_id FROM eshop.orders WHERE id=oid;
  IF mode='confirmed_email' THEN
   SELECT bank_account INTO email_bank FROM eshop.payment_info WHERE id=payment_id;
   PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
   INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(email_bank,(x->>'actor')::uuid,true);
   INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,(x->>'actor')::uuid,true);
   INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,
    physical_account,provider,mode,state,pairing_code,manifest_sha256,legacy_blocked_at)
   VALUES('capi-email','festapp',un::text,email_bank,'capi-email-'||un,'FIO','email','connected','abcdef0123',repeat('a',64),now()) RETURNING id INTO email_connection;
   SELECT jsonb_build_object('event','transaction.received','event_version','2','delivery_id','01K00000000000000000000999',
    'data',jsonb_build_object('id',un::text,'bank_account_id',un::text,'amount_cents',10000,'currency','CZK',
     'date',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
     'direction','incoming','identity_kind','observation','source','email',
     'raw_vs',variable_symbol::text,'payer_reference',creditor_reference,'counter_account','222/2010'))
    INTO email_event FROM eshop.payment_info WHERE id=payment_id;
   PERFORM public.ingest_bank_sync_transaction('capi-email','festapp',repeat('a',64),email_event);
   email_receipt:=public.confirm_bank_sync_email_observation(email_bank,email_event->>'delivery_id',payment_id,repeat('a',64),true);
   transaction_id:=(email_receipt->>'transaction_id')::bigint;
   PERFORM assert_eq(email_receipt->>'action','confirmed','CAPI fixture passes through real attested confirmation');
   PERFORM set_config('request.jwt.claim.sub','',true);
  ELSE
   INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
   SELECT bank_account,100,'CZK',now(),'fio_api' FROM eshop.payment_info WHERE id=payment_id RETURNING id INTO transaction_id;
   PERFORM public.apply_transaction_pairing(transaction_id,payment_id,'manual_attach','user');
  END IF;
  SELECT event_id INTO STRICT paid_event FROM analytics.conversion_facts WHERE "order"=oid AND kind='order_fully_paid';
  PERFORM assert_true(paid_event<>order_event,'paid fact already exists with a distinct event UUID');
  PERFORM assert_true(public.form_paid_conversion_eligible_internal(oid),'payment and live policy qualify independently of cohort');
  IF mode NOT IN ('paid','no_browser_items','confirmed_email') THEN
   PERFORM assert_false(EXISTS(SELECT FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid),
    'order/legacy/missing/non-CAPI-paid cohort is never claimed despite captured paid fact');
   -- Simulate an older worker claim: prepare must independently fence it.
   claimed:=gen_random_uuid();
   UPDATE analytics.meta_purchase_deliveries SET phone_hash=repeat('b',64),lease=claimed,lease_until=clock_timestamp()+interval '1 minute' WHERE order_id=oid;
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'order/legacy/missing/non-CAPI-paid cohort is never prepared');
   PERFORM assert_true((SELECT status='invalid' AND error_code='order_ineligible' AND attempts=0 AND consent_snapshot IS NULL
    FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'cohort rejection discloses no send payload and scrubs metadata');
  ELSE
   UPDATE analytics.meta_purchase_connectors SET enabled=false WHERE unit=un;
   PERFORM assert_false(EXISTS(SELECT FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid),'connector disabled prevents claiming an eligible paid delivery');
   UPDATE analytics.meta_purchase_connectors SET enabled=true WHERE unit=un;
   SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid;
   UPDATE analytics.meta_purchase_connectors SET enabled=false WHERE unit=un;
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'connector disabled fences a previously claimed delivery');
   UPDATE analytics.meta_purchase_connectors SET enabled=true WHERE unit=un;
   prepared:=public.prepare_meta_purchase_delivery(oid,claimed);
   PERFORM assert_eq(prepared->>'phoneHash',encode(extensions.digest('420777123456','sha256'),'hex'),'prepared payload carries phone hash');
   PERFORM assert_eq(prepared->>'fbp','fb.1.1795000000000.1234','prepared payload carries validated browser identifier');
   PERFORM assert_true(prepared->>'fbc' IS NULL,'malformed browser identifier is omitted');
   PERFORM assert_eq(prepared->>'eventId',paid_event::text,'paid cohort still prepares the original paid fact');
   UPDATE analytics.meta_purchase_deliveries SET prepared=false,client_ip='192.0.2.1',consent_at=clock_timestamp()-interval '8 days' WHERE order_id=oid;
   prepared:=public.prepare_meta_purchase_delivery(oid,claimed);
   PERFORM assert_true(prepared IS NOT NULL AND prepared->>'clientIp' IS NULL,'prepare independently suppresses expired raw addresses');
   PERFORM assert_true((SELECT client_ip IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'prepare scrubs expired raw address');
   IF mode='confirmed_email' THEN
    -- Use the real worker boundary with a fully eligible consent/cohort fixture.
    -- An unlink before prepare cancels the pending send; a sent receipt remains.
    SELECT * INTO baseline FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
    UPDATE analytics.meta_purchase_deliveries SET prepared=false WHERE order_id=oid;
    PERFORM public.apply_transaction_pairing(transaction_id,NULL,'manual_unlink','system');
    PERFORM assert_false(public.form_paid_conversion_eligible_internal(oid),'confirmed email unlinked before dispatch is ineligible');
    PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'worker refuses unlinked confirmed email');
    PERFORM assert_true((SELECT status='invalid' AND error_code='order_ineligible' FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'worker records ineligible receipt');
    PERFORM public.apply_transaction_pairing(transaction_id,payment_id,'manual_attach','system');
    UPDATE analytics.meta_purchase_deliveries SET status='pending',lease=claimed,
      lease_until=clock_timestamp()+interval '2 minutes',prepared=true,prepared_at=clock_timestamp(),done_at=NULL WHERE order_id=oid;
    PERFORM assert_true(public.finish_meta_purchase_delivery(oid,claimed,'sent'),'confirmed bank email sent receipt finalized');
    SELECT * INTO baseline FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
    PERFORM public.apply_transaction_pairing(transaction_id,NULL,'manual_unlink','system');
    PERFORM assert_true((SELECT status='sent' AND done_at=baseline.done_at FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'unlink after dispatch retains sent receipt and timestamp');
    PERFORM assert_false(EXISTS(SELECT FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid),'sent receipt cannot be claimed again');
    CONTINUE;
   END IF;
   IF mode='paid' THEN
    SELECT * INTO baseline FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
    SELECT created_at INTO paid_at FROM analytics.conversion_facts WHERE "order"=oid AND kind='order_fully_paid';
    INSERT INTO public.organization_users(organization,"user",is_admin) VALUES((x->>'organization')::bigint,(x->>'actor')::uuid,true);
    PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
    FOREACH reason_case IN ARRAY ARRAY['connector_changed','consent_revision','snapshot_denied','consent_age','consent_after_payment','order_ineligible','form_disabled','payment_too_old','attempts_exhausted','retention_expired'] LOOP
     UPDATE analytics.meta_purchase_deliveries SET status='pending',error_code=NULL,done_at=NULL,prepared=false,
      lease=claimed,lease_until=clock_timestamp()+interval '1 minute',attempts=0,
      connector_revision=baseline.connector_revision,consent_revision=baseline.consent_revision,
      consent_snapshot=baseline.consent_snapshot,consent_at=statement_timestamp()-interval '1 second',email_hash=repeat('a',64)
     WHERE order_id=oid;
     expected_reason:=reason_case;
     IF reason_case='connector_changed' THEN
      UPDATE analytics.meta_purchase_deliveries SET connector_revision=gen_random_uuid() WHERE order_id=oid;
     ELSIF reason_case IN ('consent_revision','snapshot_denied','consent_age','consent_after_payment') THEN
      expected_reason:='consent_invalid';
      IF reason_case='consent_revision' THEN
       UPDATE analytics.meta_purchase_deliveries SET consent_revision='obsolete' WHERE order_id=oid;
      ELSIF reason_case='snapshot_denied' THEN
       UPDATE analytics.meta_purchase_deliveries SET consent_snapshot=consent_snapshot||'{"ad_storage":false}' WHERE order_id=oid;
      ELSIF reason_case='consent_age' THEN
       UPDATE analytics.meta_purchase_deliveries SET consent_at=clock_timestamp()-interval '31 days' WHERE order_id=oid;
      ELSE
       UPDATE analytics.meta_purchase_deliveries SET consent_at=clock_timestamp()+interval '1 minute' WHERE order_id=oid;
      END IF;
     ELSIF reason_case='order_ineligible' THEN
      UPDATE analytics.conversion_facts SET payload=payload||'{"value":999}' WHERE "order"=oid AND kind='order_fully_paid';
     ELSIF reason_case='form_disabled' THEN
      expected_reason:='order_ineligible';
      DELETE FROM analytics.meta_purchase_forms WHERE form=fid;
     ELSIF reason_case='payment_too_old' THEN
      UPDATE analytics.conversion_facts SET created_at=clock_timestamp()-interval '8 days' WHERE "order"=oid AND kind='order_fully_paid';
      UPDATE analytics.meta_purchase_deliveries SET consent_at=clock_timestamp()-interval '9 days' WHERE order_id=oid;
     ELSIF reason_case='attempts_exhausted' THEN
      UPDATE analytics.meta_purchase_deliveries SET attempts=6 WHERE order_id=oid;
     ELSE
      UPDATE analytics.meta_purchase_deliveries SET consent_at=clock_timestamp()-interval '31 days' WHERE order_id=oid;
     END IF;
     IF reason_case='retention_expired' THEN
      PERFORM public.purge_meta_purchase_data_internal();
     ELSE
      PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'terminal guard rejects: '||reason_case);
     END IF;
     PERFORM assert_true((SELECT status=CASE WHEN reason_case='retention_expired' THEN 'expired' ELSE 'invalid' END
      AND error_code=expected_reason AND consent_snapshot IS NULL AND email_hash IS NULL AND phone_hash IS NULL
      AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL AND client_agent IS NULL AND source_url IS NULL
      AND lease IS NULL AND lease_until IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'stable reason and scrub: '||reason_case);
     overview:=public.get_unit_meta_purchase(un);
     PERFORM assert_eq(overview#>>'{last_error,code}',expected_reason,'overview explains: '||reason_case);
     PERFORM assert_eq(overview#>>'{last_error,status}',CASE WHEN reason_case='retention_expired' THEN 'expired' ELSE 'invalid' END,'overview terminal status');
     PERFORM assert_eq(overview#>>ARRAY['queue',CASE WHEN reason_case='retention_expired' THEN 'expired' ELSE 'invalid' END],'1','recent outcome counted even after consent expires');
     UPDATE analytics.meta_purchase_deliveries SET done_at=clock_timestamp()-interval '31 days',consent_at=clock_timestamp()-interval '40 days' WHERE order_id=oid;
     PERFORM assert_eq(public.get_unit_meta_purchase(un)#>>ARRAY['queue',CASE WHEN reason_case='retention_expired' THEN 'expired' ELSE 'invalid' END],'0','old outcome excluded');
     UPDATE analytics.conversion_facts SET created_at=paid_at,payload=jsonb_build_object('value',100,'currency','CZK') WHERE "order"=oid AND kind='order_fully_paid';
     IF reason_case='form_disabled' THEN INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES(fid,un); END IF;
    END LOOP;
    UPDATE analytics.meta_purchase_deliveries SET status='pending',error_code=NULL,done_at=NULL,connector_revision=baseline.connector_revision,
     consent_revision=baseline.consent_revision,consent_snapshot=baseline.consent_snapshot,attempts=0,lease=claimed,
     lease_until=clock_timestamp()+interval '1 minute' WHERE order_id=oid;
    UPDATE analytics.meta_purchase_deliveries SET prepared=false,consent_at=clock_timestamp() WHERE order_id=oid;
    UPDATE analytics.meta_purchase_connectors SET revision=gen_random_uuid() WHERE unit=un;
    PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'old connector revision never sends');
    PERFORM assert_true((SELECT status='invalid' AND email_hash IS NULL AND consent_snapshot IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'revision invalidation erases matching data');
    -- Disconnect also scrubs pending rows and retains their terminal audit state.
    PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
    UPDATE analytics.meta_purchase_deliveries SET status='pending',phone_hash=repeat('b',64) WHERE order_id=oid;
    SELECT vault_secret INTO claimed FROM analytics.meta_purchase_connectors WHERE unit=un;
    PERFORM public.delete_unit_meta_purchase(un);
    PERFORM assert_true((SELECT status='revoked' AND consent_snapshot IS NULL AND email_hash IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL AND client_agent IS NULL AND source_url IS NULL AND lease IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'disconnect terminates pending delivery and erases matching data');
    PERFORM assert_false(EXISTS(SELECT FROM vault.secrets WHERE id=claimed),'disconnect deletes the delivery token');
    CONTINUE;
   END IF;
   UPDATE analytics.meta_purchase_deliveries SET prepared=true,phone_hash=repeat('b',64),fbp='fb.1.1795000000000.1234',fbc='fb.1.1795000000000.Click_123',client_ip='192.0.2.1' WHERE order_id=oid;
   PERFORM assert_true(public.finish_meta_purchase_delivery(oid,claimed,'rejected'),'rejected delivery is finalized');
   PERFORM assert_true((SELECT status='failed' AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'failed delivery erases all matching');
  END IF;
 END LOOP;
END $$;

DO $$ BEGIN
 PERFORM assert_true(public.meta_purchase_phone_internal('777 123 456') IS NULL,'ambiguous national number is omitted');
 PERFORM assert_eq(public.meta_purchase_phone_internal('777 123 456','+420'),'420777123456','one saved Czech prefix is enough');
 PERFORM assert_eq(public.meta_purchase_phone_internal('00 421 905 123 456'),'421905123456','international 00 prefix');
 PERFORM assert_eq(public.meta_purchase_phone_internal('905123456','+421'),'421905123456','saved Slovak default');
 PERFORM assert_eq(public.meta_purchase_phone_internal('0903 123 456','+421'),'421903123456','Slovak national trunk 0 is dropped');
 PERFORM assert_eq(public.meta_purchase_phone_internal('030 12345678','+49'),'493012345678','German national number with trunk 0');
 PERFORM assert_eq(public.meta_purchase_phone_internal('06 1234 5678','+39'),'390612345678','Italian numbers keep the leading 0');
 PERFORM assert_true(public.meta_purchase_phone_internal('777 123 456','bad') IS NULL,'an invalid saved prefix is not used');
 PERFORM assert_true(public.meta_purchase_phone_internal('bad') IS NULL AND public.meta_purchase_phone_internal('+420 1') IS NULL
  AND public.meta_purchase_phone_internal('+420 000 000 000') IS NULL AND public.meta_purchase_phone_internal('+420 (0)777123456') IS NULL,'invalid phones are excluded');
 PERFORM assert_true(public.meta_purchase_browser_id_internal(E'fb.1.1795000000000.123\n') IS NULL
  AND public.meta_purchase_browser_id_internal('fb.1.1795000000000.'||repeat('x',501)) IS NULL,'browser identifiers reject controls and oversized values');
 PERFORM assert_true(public.meta_purchase_ip_internal('192.0.2.1') IS NOT NULL AND public.meta_purchase_ip_internal('2001:db8::1') IS NOT NULL,'IPv4 and IPv6 accepted');
 PERFORM assert_true(public.meta_purchase_ip_internal('999.1.1.1') IS NULL AND public.meta_purchase_ip_internal('192.0.2.1/24') IS NULL
  AND public.meta_purchase_ip_internal('192.0.2.1, 192.0.2.2') IS NULL AND public.meta_purchase_ip_internal('192.1') IS NULL,'invalid addresses, lists and subnets excluded');
END $$;

-- Prepare is the irreversible send boundary. Withdrawal still erases all data
-- immediately while preserving only the receipt fence for the current sender.
DO $$
DECLARE x jsonb; un bigint; fid bigint; snapshot jsonb; receipt jsonb; oid bigint;
 payment_id bigint; transaction_id bigint; claimed uuid; deadline timestamptz; result text;
BEGIN
 FOREACH result IN ARRAY ARRAY['sent','sent_test_inactive','retry','credentials','rejected','before_prepare','expired_lease'] LOOP
  x:=pg_temp.fixture(NULL); un:=(x->>'unit')::bigint; fid:=(x->>'form')::bigint;
  PERFORM set_config('request.jwt.claim.sub','',true);
  UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=(x->>'organization')::bigint;
  INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
  VALUES((x->>'organization')::bigint,true,1,'fixture','in-flight withdrawal');
  UPDATE public.forms SET is_open=true,data=data||'{"analytics":{"enabled":true}}' WHERE id=fid;
  PERFORM public.reserve_public_link_internal('form',fid,x->>'link',true);
  INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled)
  VALUES(un,'123456',vault.create_secret(repeat('t',40),'revocation-flight-'||un),'https://tickets.example',true);
  INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES(fid,un);
  PERFORM public.purge_meta_purchase_data_internal();
  snapshot:=jsonb_build_object('source','klaro','capturedAt',to_char((clock_timestamp()-interval '1 second') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal(un)->>'consentRevision',
   'revision',public.get_meta_purchase_consent(x->>'link')->>'revision','userAgent','Withdrawal regression',
   'ad_storage',true,'ad_user_data',true,'ad_personalization',true);
  receipt:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||jsonb_build_object('metaPurchaseConsent',snapshot,'email','withdrawal-'||result||'-'||un::text||'@example.invalid'),gen_random_uuid(),gen_random_uuid());
  PERFORM assert_eq(receipt#>>'{data,code}','200','withdrawal fixture checkout succeeds');
  oid:=(receipt#>>'{data,order,id}')::bigint;
  SELECT payment_info INTO STRICT payment_id FROM eshop.orders WHERE id=oid;
  INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
  SELECT bank_account,100,'CZK',now(),'fio_api' FROM eshop.payment_info WHERE id=payment_id RETURNING id INTO transaction_id;
  PERFORM public.apply_transaction_pairing(transaction_id,payment_id,'manual_attach','user');
  SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid;
  IF result<>'before_prepare' THEN
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NOT NULL,'valid delivery prepares before withdrawal');
  END IF;
  IF result='expired_lease' THEN
   UPDATE analytics.meta_purchase_deliveries SET lease_until=clock_timestamp()-interval '1 second' WHERE order_id=oid;
  END IF;
  SELECT next_attempt_at INTO deadline FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
  PERFORM public.issue_order_overview_internal(oid,pg_temp.delivery('fixture',encode(sha256(convert_to('withdrawal-'||result,'UTF8')),'hex'),oid),gen_random_uuid());
  PERFORM assert_true(public.revoke_meta_purchase_consent(encode(sha256(convert_to('withdrawal-'||result,'UTF8')),'hex'),oid),'buyer withdraws consent');
  PERFORM assert_true((SELECT status='revoked' AND revoked_at IS NOT NULL AND consent_snapshot IS NULL
   AND email_hash IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL
   AND client_agent IS NULL AND source_url IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
   'withdrawal immediately erases the entire matching payload');
  PERFORM assert_false(public.finish_meta_purchase_delivery(oid,gen_random_uuid(),'sent'),'foreign lease cannot finish a revoked delivery');
  IF result IN ('before_prepare','expired_lease') THEN
   PERFORM assert_true((SELECT lease IS NULL AND lease_until IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
    'unprepared or expired lease is cleared');
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'withdrawal before prepare blocks sending');
   PERFORM assert_false(public.finish_meta_purchase_delivery(oid,claimed,'sent'),'cleared lease cannot finish');
  ELSE
   PERFORM assert_true((SELECT lease=claimed AND lease_until>clock_timestamp() FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
    'prepared live receipt fence survives withdrawal');
   PERFORM assert_true(public.revoke_meta_purchase_consent(encode(sha256(convert_to('withdrawal-'||result,'UTF8')),'hex'),oid),'repeated withdrawal is harmless');
   PERFORM assert_true(public.finish_meta_purchase_delivery(oid,claimed,result),'sender records the in-flight result');
   PERFORM assert_eq((SELECT error_code FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
    CASE WHEN result IN ('sent','sent_test_inactive') THEN 'sent_in_flight' ELSE result END,'receipt preserves the actual outcome');
   PERFORM assert_false(public.finish_meta_purchase_delivery(oid,claimed,result),'receipt fence is consumed once');
   IF result='credentials' THEN
    PERFORM assert_true((SELECT paused_at IS NOT NULL FROM analytics.meta_purchase_connectors WHERE unit=un),'credentials still pause connector');
   END IF;
  END IF;
  PERFORM assert_true((SELECT status='revoked' AND revoked_at IS NOT NULL AND lease IS NULL AND lease_until IS NULL
   AND next_attempt_at=deadline AND consent_snapshot IS NULL AND email_hash IS NULL AND phone_hash IS NULL
   AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL AND client_agent IS NULL AND source_url IS NULL
   FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'finish never restores data or schedules a revoked delivery');
  PERFORM assert_false(EXISTS(SELECT FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid),'revoked delivery cannot be claimed');
  PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'revoked delivery cannot prepare again');
 END LOOP;
END $$;

-- Organizer settings: stored scope, policy, Vault and write-only projections.
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); other jsonb:=pg_temp.fixture(NULL);
 un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
 fid bigint:=(x->>'form')::bigint; result jsonb; old_revision uuid; secret_id uuid; changed_time timestamptz;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 BEGIN PERFORM public.get_unit_meta_purchase(un); RAISE EXCEPTION 'non-admin read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.save_unit_meta_purchase(un,'123456','https://tickets.example',NULL,true,repeat('s',32)); RAISE EXCEPTION 'non-admin save accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.set_form_meta_purchase(un,fid,true); RAISE EXCEPTION 'non-admin form accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.delete_unit_meta_purchase(un); RAISE EXCEPTION 'non-admin delete accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,(x->>'actor')::uuid,true);
 PERFORM assert_true(public.get_unit_meta_purchase(un) ? 'websites','admin can configure without an organization measurement policy');
 BEGIN PERFORM public.get_unit_meta_purchase((other->>'unit')::bigint); RAISE EXCEPTION 'foreign organization read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.save_unit_meta_purchase((other->>'unit')::bigint,'123456','https://tickets.example',NULL,true,repeat('s',32)); RAISE EXCEPTION 'foreign save accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.set_form_meta_purchase((other->>'unit')::bigint,(other->>'form')::bigint,true); RAISE EXCEPTION 'foreign form accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.delete_unit_meta_purchase((other->>'unit')::bigint); RAISE EXCEPTION 'foreign delete accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES(org,true,1,'fixture','CAPI settings');
 UPDATE public.units SET data=coalesce(data,'{}'::jsonb)||'{"measurement_websites":["https://tickets.example"]}'::jsonb WHERE id=un;
 BEGIN
  PERFORM public.save_unit_meta_purchase(un,'123456','https://tickets.example',NULL,true);
  RAISE EXCEPTION 'enabled connector without a token accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_connectors WHERE unit=un),'failed enable leaves no partial connector');
 result:=public.save_unit_meta_purchase(un,'123456','https://tickets.example',NULL,false);
 old_revision:=(result->>'revision')::uuid;
 PERFORM assert_true(result->'websites' ? 'https://tickets.example','saved website is selectable without a runtime deployment');
 PERFORM assert_false((result->>'token_saved')::boolean,'new connector has no token');
 PERFORM assert_true(result->>'token_hint' IS NULL AND result->>'token_changed_at' IS NULL,'settings without a token store no hint');
 BEGIN PERFORM public.save_unit_meta_purchase(un,'123456','https://attacker.example',NULL,true); RAISE EXCEPTION 'foreign origin accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.save_unit_meta_purchase(un,'654321','https://tickets.example','TEST42',true,E'secret\ntoo-short'); RAISE EXCEPTION 'invalid token accepted';
 EXCEPTION WHEN invalid_parameter_value THEN PERFORM assert_true(SQLERRM='Invalid Meta CAPI token','token validation does not echo input'); END;
 PERFORM assert_true((SELECT dataset='123456' AND test_event_code IS NULL AND NOT enabled AND revision=old_revision
  FROM analytics.meta_purchase_connectors WHERE unit=un),'invalid replacement keeps the saved configuration');
 UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp() WHERE unit=un;
 PERFORM public.save_unit_meta_purchase(un,'123456','https://tickets.example',NULL,true,repeat('secret-value-',3));
 SELECT vault_secret INTO secret_id FROM analytics.meta_purchase_connectors WHERE unit=un;
 PERFORM assert_true(EXISTS(SELECT FROM vault.secrets WHERE id=secret_id),'token created in Vault');
 result:=public.get_unit_meta_purchase(un);
 PERFORM assert_true(result->'paused_at'='null'::jsonb AND result->'token_saved'='true'::jsonb,'saving token clears pause');
 PERFORM assert_false(result ? 'vault_secret' OR result ? 'token' OR result::text LIKE '%secret-value-%','projection contains no credential');
 PERFORM assert_eq(result->>'token_hint',right(repeat('secret-value-',3),10),'saved token exposes only its last ten characters');
 PERFORM assert_true(result->>'token_changed_at' IS NOT NULL,'saved token records its change time');
 changed_time:=(result->>'token_changed_at')::timestamptz;
 BEGIN
  UPDATE analytics.meta_purchase_connectors SET token_hint=repeat('x',11) WHERE unit=un;
  RAISE EXCEPTION 'overlong token hint accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  UPDATE analytics.meta_purchase_connectors SET token_hint=E'abc\ndef' WHERE unit=un;
  RAISE EXCEPTION 'control character in token hint accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 result:=public.save_unit_meta_purchase(un,'654321','https://tickets.example',NULL,true,repeat('replacement-',3));
 PERFORM assert_true((SELECT vault_secret=secret_id FROM analytics.meta_purchase_connectors WHERE unit=un),'token replacement reuses secret');
 PERFORM assert_true((result->>'revision')::uuid<>old_revision,'dataset change advances revision');
 PERFORM assert_eq(result->>'token_hint','placement-','token replacement updates the hint');
 PERFORM assert_true((result->>'token_changed_at')::timestamptz>changed_time,'token replacement advances its change time');
 PERFORM assert_false(result::text LIKE '%'||repeat('replacement-',3)||'%','projection never contains the full token');
 changed_time:=(result->>'token_changed_at')::timestamptz;
 result:=public.save_unit_meta_purchase(un,'654321','https://tickets.example',NULL,true);
 PERFORM assert_true(result->>'token_hint'='placement-' AND (result->>'token_changed_at')::timestamptz=changed_time,
  'saving settings without a token keeps the saved hint and change time');
 PERFORM public.set_form_meta_purchase(un,fid,true);
 BEGIN PERFORM public.set_form_meta_purchase(un,(other->>'form')::bigint,true); RAISE EXCEPTION 'foreign form accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM assert_eq((SELECT capi_unit FROM public.form_measurement_decision_internal(fid)),un,'configured organizer selected');
 UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp() WHERE unit=un;
 PERFORM assert_true((SELECT capi_unit FROM public.form_measurement_decision_internal(fid)) IS NULL,'pause blocks CAPI collection');
 PERFORM assert_eq((SELECT purchase_timing FROM public.form_measurement_decision_internal(fid)),'paid','pause preserves paid browser timing');
 UPDATE analytics.meta_purchase_connectors SET paused_at=NULL WHERE unit=un;
 UPDATE analytics.meta_purchase_connectors SET enabled=false WHERE unit=un;
 PERFORM assert_true((SELECT capi_unit FROM public.form_measurement_decision_internal(fid)) IS NULL,'connector disabled blocks collection');
 PERFORM assert_eq((SELECT purchase_timing FROM public.form_measurement_decision_internal(fid)),'order','explicitly disabling the connector restores the form purchase timing');
 PERFORM assert_false(public.meta_purchase_snapshot_valid_internal(un,'{}'::jsonb),'connector disabled blocks consent');
 UPDATE analytics.meta_purchase_connectors SET enabled=true WHERE unit=un;
 PERFORM public.delete_unit_meta_purchase(un);
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_connectors WHERE unit=un),'disconnect removes connector');
 PERFORM assert_false(EXISTS(SELECT FROM vault.secrets WHERE id=secret_id),'disconnect erases Vault secret');
 PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_forms WHERE unit=un),'disconnect removes form switches');
 result:=public.get_unit_meta_purchase(un);
 PERFORM assert_false(result ? 'token_hint' OR result ? 'token_changed_at','disconnect clears the token hint');
END $$;
-- Disconnect after disabling the connector follows the same prepared receipt fence as consent withdrawal.
DO $$
DECLARE x jsonb; un bigint; fid bigint; snapshot jsonb; receipt jsonb; oid bigint;
 payment_id bigint; transaction_id bigint; claimed uuid; deadline timestamptz; result text; secret_id uuid;
BEGIN
 FOREACH result IN ARRAY ARRAY['sent','retry','credentials','rejected','before_prepare','expired_lease'] LOOP
  x:=pg_temp.fixture(NULL); un:=(x->>'unit')::bigint; fid:=(x->>'form')::bigint;
  PERFORM set_config('request.jwt.claim.sub','',true);
  UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=(x->>'organization')::bigint;
  INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
  VALUES((x->>'organization')::bigint,true,1,'fixture','in-flight disconnect');
  UPDATE public.forms SET is_open=true,data=data||'{"analytics":{"enabled":true}}' WHERE id=fid;
  PERFORM public.reserve_public_link_internal('form',fid,x->>'link',true);
  INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled)
  VALUES(un,'123456',vault.create_secret(repeat('t',40),'disconnect-flight-'||un),'https://tickets.example',true);
  INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES(fid,un);
  PERFORM public.purge_meta_purchase_data_internal();
  snapshot:=jsonb_build_object('source','klaro','capturedAt',to_char((clock_timestamp()-interval '1 second') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal(un)->>'consentRevision',
   'revision',public.get_meta_purchase_consent(x->>'link')->>'revision','userAgent','Disconnect regression',
   'ad_storage',true,'ad_user_data',true,'ad_personalization',true);
  receipt:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||jsonb_build_object('metaPurchaseConsent',snapshot,'email','disconnect-'||result||'-'||un::text||'@example.invalid'),gen_random_uuid(),gen_random_uuid());
  PERFORM assert_eq(receipt#>>'{data,code}','200','disconnect fixture checkout succeeds');
  oid:=(receipt#>>'{data,order,id}')::bigint;
  SELECT payment_info INTO STRICT payment_id FROM eshop.orders WHERE id=oid;
  INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
  SELECT bank_account,100,'CZK',now(),'fio_api' FROM eshop.payment_info WHERE id=payment_id RETURNING id INTO transaction_id;
  PERFORM public.apply_transaction_pairing(transaction_id,payment_id,'manual_attach','user');
  SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid;
  IF result<>'before_prepare' THEN
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NOT NULL,'valid delivery prepares before disconnect');
  END IF;
  IF result='expired_lease' THEN
   UPDATE analytics.meta_purchase_deliveries SET lease_until=clock_timestamp()-interval '1 second' WHERE order_id=oid;
  END IF;
  SELECT next_attempt_at INTO deadline FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
  -- Every disconnect below happens after the connector has been disabled.
  UPDATE analytics.meta_purchase_connectors SET enabled=false WHERE unit=un;
  PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'connector disabled blocks preparation even with a claimed lease');
  IF result='before_prepare' THEN
   PERFORM assert_true((SELECT NOT prepared AND attempts=0 AND status='pending' FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
    'a disabled connector authorizes no send and consumes no attempt');
  END IF;
  PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
  BEGIN
   PERFORM public.delete_unit_meta_purchase(un);
   RAISE EXCEPTION 'non-admin disconnect accepted after connector disabled';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO public.organization_users(organization,"user",is_admin) VALUES((x->>'organization')::bigint,(x->>'actor')::uuid,true);
  SELECT vault_secret INTO secret_id FROM analytics.meta_purchase_connectors WHERE unit=un;
  PERFORM public.delete_unit_meta_purchase(un);
  PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_connectors WHERE unit=un),'disconnect removes connector despite connector disabled');
  PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_forms WHERE unit=un),'disconnect removes form switches');
  PERFORM assert_false(EXISTS(SELECT FROM vault.secrets WHERE id=secret_id),'disconnect deletes Vault secret');
  PERFORM assert_true((SELECT status='revoked' AND revoked_at IS NOT NULL AND consent_snapshot IS NULL
   AND consent_scope IS NULL AND consent_decided_at IS NULL AND email_hash IS NULL AND phone_hash IS NULL
   AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL AND client_agent IS NULL AND source_url IS NULL
   FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'disconnect keeps audit row through connector FK deletion and scrubs all matching data');
  PERFORM public.delete_unit_meta_purchase(un);
  PERFORM assert_false(public.finish_meta_purchase_delivery(oid,gen_random_uuid(),'sent'),'foreign lease cannot finish after disconnect');
  IF result IN ('before_prepare','expired_lease') THEN
   PERFORM assert_true((SELECT lease IS NULL AND lease_until IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'unprepared or expired fence cleared on disconnect');
   PERFORM assert_false(public.finish_meta_purchase_delivery(oid,claimed,'sent'),'cleared disconnect fence cannot finish');
  ELSE
   PERFORM assert_true((SELECT prepared AND lease=claimed AND lease_until>clock_timestamp() FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'repeated disconnect retains live sender fence');
   PERFORM assert_true(public.finish_meta_purchase_delivery(oid,claimed,result),'finish succeeds without connector, including credentials');
   PERFORM assert_eq((SELECT error_code FROM analytics.meta_purchase_deliveries WHERE order_id=oid),CASE WHEN result='sent' THEN 'sent_in_flight' ELSE result END,'disconnected receipt records real outcome');
   PERFORM assert_false(public.finish_meta_purchase_delivery(oid,claimed,result),'disconnected receipt is consumed once');
   PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_connectors WHERE unit=un),'credentials cannot recreate disconnected connector');
  END IF;
  PERFORM assert_true((SELECT status='revoked' AND lease IS NULL AND lease_until IS NULL AND next_attempt_at=deadline
   AND consent_snapshot IS NULL AND consent_scope IS NULL AND consent_decided_at IS NULL AND email_hash IS NULL
   AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL AND client_agent IS NULL AND source_url IS NULL
   FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'finish neither restores data nor reschedules disconnected delivery');
  PERFORM assert_false(EXISTS(SELECT FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid),'disconnected delivery cannot be reclaimed');
  PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'disconnected delivery cannot prepare again');
 END LOOP;
END $$;

-- Connector locks and token timestamps fence optional capture and delivery.
DO $$
DECLARE x jsonb; un bigint; fid bigint; snapshot jsonb; receipt jsonb; oid bigint;
 payment_id bigint; transaction_id bigint; claimed uuid; result text;
 prepared_time timestamptz; changed_time timestamptz; captured_revision uuid; captured_time timestamptz;
BEGIN
 FOREACH result IN ARRAY ARRAY['capture_after_disconnect','capture_compatible_lock','disabled','dataset','form_disabled','invalid_token','legacy_token','older_token','newer_token','equal_token','new_revision','legacy_prepare','final_failure'] LOOP
  x:=pg_temp.fixture(NULL); un:=(x->>'unit')::bigint; fid:=(x->>'form')::bigint;
  PERFORM set_config('request.jwt.claim.sub','',true);
  UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=(x->>'organization')::bigint;
  INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
  VALUES((x->>'organization')::bigint,true,1,'fixture','connector locking');
  UPDATE public.forms SET is_open=true,data=data||'{"analytics":{"enabled":true}}' WHERE id=fid;
  PERFORM public.reserve_public_link_internal('form',fid,x->>'link',true);
  INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled)
  VALUES(un,'123456',vault.create_secret(repeat('t',40),'connector-lock-'||un),'https://tickets.example',true);
  INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES(fid,un);
  PERFORM public.purge_meta_purchase_data_internal();
  snapshot:=jsonb_build_object('source','klaro','capturedAt',to_char((clock_timestamp()-interval '1 second') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal(un)->>'consentRevision',
   'revision',public.get_meta_purchase_consent(x->>'link')->>'revision','userAgent','Connector lock regression',
   'ad_storage',true,'ad_user_data',true,'ad_personalization',true);
  receipt:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||jsonb_build_object('metaPurchaseConsent',snapshot,'email','connector-lock-'||result||'-'||un::text||'@example.invalid'),gen_random_uuid(),gen_random_uuid());
  PERFORM assert_eq(receipt#>>'{data,code}','200','connector locking fixture checkout succeeds');
  oid:=(receipt#>>'{data,order,id}')::bigint;
  SELECT payment_info INTO STRICT payment_id FROM eshop.orders WHERE id=oid;
  INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
  SELECT bank_account,100,'CZK',now(),'fio_api' FROM eshop.payment_info WHERE id=payment_id RETURNING id INTO transaction_id;
  PERFORM public.apply_transaction_pairing(transaction_id,payment_id,'manual_attach','user');
  SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid;

  INSERT INTO public.organization_users(organization,"user",is_admin) VALUES((x->>'organization')::bigint,(x->>'actor')::uuid,true);
  UPDATE public.units SET data=coalesce(data,'{}'::jsonb)||'{"measurement_websites":["https://tickets.example"]}'::jsonb WHERE id=un;
  SELECT revision INTO captured_revision FROM analytics.meta_purchase_connectors WHERE unit=un;
  PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
  IF result='capture_compatible_lock' THEN
   -- Fixtures are uncommitted and invisible to a second dblink connection.
   -- Exercise capture under the routine writer lock in this transaction and
   -- verify the exact cross-session-compatible modes in the lock contract below.
   SELECT consent_at INTO captured_time FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
   DELETE FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
   PERFORM 1 FROM analytics.meta_purchase_connectors WHERE unit=un FOR NO KEY UPDATE;
   PERFORM assert_true(EXISTS(SELECT FROM pg_locks WHERE pid=pg_backend_pid()
    AND relation='analytics.meta_purchase_connectors'::regclass
    AND mode='RowShareLock' AND granted),'routine connector row lock is held');
   PERFORM set_config('request.jwt.claim.sub','',true);
   PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot);
   PERFORM assert_true((SELECT connector_revision=captured_revision AND status='pending' FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
    'capture under a routine writer lock retains optional matching');
   -- Preserve the original pre-payment capture time for isolated revision validation.
   UPDATE analytics.meta_purchase_deliveries SET consent_at=captured_time WHERE order_id=oid;
   -- An edit may overlap key-share capture; it must never redirect that purchase.
   PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
   PERFORM public.save_unit_meta_purchase(un,'654321','https://tickets.example',NULL,true);
   PERFORM set_config('request.jwt.claim.sub','',true);
   SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid;
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'a capture from the previous dataset revision never sends');
   PERFORM assert_true((SELECT status='invalid' AND consent_snapshot IS NULL AND email_hash IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),
    'a dataset edit invalidates and scrubs capture with the old revision');
   CONTINUE;
  ELSIF result='capture_after_disconnect' THEN
   -- Model an earlier check that observed a live connector. The actual capture
   -- must re-read and lock it after delete has completed, not trust that check.
   PERFORM assert_true(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'valid fixture captured before disconnect');
   DELETE FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
   UPDATE analytics.meta_purchase_connectors SET enabled=false WHERE unit=un;
   PERFORM public.delete_unit_meta_purchase(un);
   UPDATE analytics.meta_purchase_connectors SET enabled=true WHERE unit=un;
   PERFORM set_config('request.jwt.claim.sub','',true);
   PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot);
   PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'capture after disconnect cannot reinsert matching data');
   receipt:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||jsonb_build_object('metaPurchaseConsent',snapshot,'email','after-disconnect-'||un::text||'@example.invalid'),gen_random_uuid(),gen_random_uuid());
   PERFORM assert_eq(receipt#>>'{data,code}','200','stale optional consent never breaks checkout after disconnect');
   PERFORM assert_false(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=(receipt#>>'{data,order,id}')::bigint),'new checkout after disconnect collects no matching data');
   CONTINUE;
  ELSIF result='disabled' THEN
   PERFORM public.save_unit_meta_purchase(un,'123456','https://tickets.example',NULL,false);
  ELSIF result='dataset' THEN
   PERFORM public.save_unit_meta_purchase(un,'654321','https://tickets.example',NULL,true);
  ELSIF result='form_disabled' THEN
   PERFORM public.set_form_meta_purchase(un,fid,false);
  ELSIF result='invalid_token' THEN
   PERFORM vault.update_secret((SELECT vault_secret FROM analytics.meta_purchase_connectors WHERE unit=un),'short');
  ELSIF result='final_failure' THEN
   UPDATE analytics.meta_purchase_deliveries SET attempts=5 WHERE order_id=oid;
  ELSIF result='older_token' THEN
   PERFORM public.save_unit_meta_purchase(un,'123456','https://tickets.example',NULL,true,repeat('older-token-',3));
  END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  IF result IN ('disabled','dataset','form_disabled') THEN
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'prepare rejects changed or disabled connector');
   PERFORM assert_true((SELECT attempts=0 AND NOT prepared AND prepared_at IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'rejected prepare consumes no send attempt or timestamp');
   IF result IN ('dataset','form_disabled') THEN
    PERFORM assert_true((SELECT status='invalid' AND consent_snapshot IS NULL AND email_hash IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'destination change invalidates and scrubs the old revision');
   END IF;
   CONTINUE;
  END IF;
  IF result='invalid_token' THEN
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'invalid Vault token returns no payload');
   PERFORM assert_true((SELECT paused_at IS NOT NULL FROM analytics.meta_purchase_connectors WHERE unit=un),'invalid token pauses the connector without upgrading a shared lock');
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'another prepare sees the credential pause');
   PERFORM assert_true((SELECT attempts=0 AND NOT prepared FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'credential pause consumes no send attempt');
   CONTINUE;
  END IF;
  PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NOT NULL,'unchanged connector prepares a valid paid payload');
  SELECT prepared_at INTO prepared_time FROM analytics.meta_purchase_deliveries WHERE order_id=oid;
  PERFORM assert_true(prepared_time IS NOT NULL,'prepare records the authorization instant');
  PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
  IF result IN ('newer_token','equal_token','legacy_prepare') THEN
   PERFORM public.save_unit_meta_purchase(un,'123456','https://tickets.example',NULL,true,repeat('replacement-token-',3));
   SELECT token_changed_at INTO changed_time FROM analytics.meta_purchase_connectors WHERE unit=un;
   PERFORM assert_true(changed_time>=prepared_time,'token replacement records a time after prepare');
   PERFORM assert_true((SELECT revision=captured_revision FROM analytics.meta_purchase_connectors WHERE unit=un),'token replacement does not change destination revision');
   IF result='equal_token' THEN
    UPDATE analytics.meta_purchase_connectors SET token_changed_at=prepared_time WHERE unit=un;
   ELSIF result='legacy_prepare' THEN
    UPDATE analytics.meta_purchase_deliveries SET prepared_at=NULL WHERE order_id=oid;
   END IF;
  ELSIF result='older_token' THEN
   PERFORM assert_true((SELECT token_changed_at<prepared_time FROM analytics.meta_purchase_connectors WHERE unit=un),'previous token predates prepare');
  ELSIF result='new_revision' THEN
   UPDATE analytics.meta_purchase_connectors SET revision=gen_random_uuid() WHERE unit=un;
  ELSE
   PERFORM assert_true((SELECT token_changed_at IS NULL FROM analytics.meta_purchase_connectors WHERE unit=un),'legacy token keeps its unknown change time');
  END IF;
  PERFORM assert_true(public.finish_meta_purchase_delivery(oid,claimed,'credentials'),'credential outcome consumes the prepared receipt');
  PERFORM assert_true((SELECT (paused_at IS NOT NULL)=(result IN ('legacy_token','older_token','final_failure')) FROM analytics.meta_purchase_connectors WHERE unit=un),
   'only a matching revision with an older/legacy token is paused; replacement tokens survive old credential failures');
  PERFORM assert_eq(public.get_unit_meta_purchase(un)#>>'{last_error,status}',
   CASE WHEN result='final_failure' THEN 'failed' ELSE 'pending' END,
   'redacted last error distinguishes terminal failure from scheduled retry even for the same credential code');
  PERFORM assert_false(public.finish_meta_purchase_delivery(oid,claimed,'credentials'),'credential receipt cannot replay after rotation');
 END LOOP;
END $$;

-- Row lock modes are part of the concurrency contract. The single-transaction
-- behavior cases above cannot reproduce lock upgrading or wait timing across
-- sessions; pin the actual lock clauses as well as their observable outcomes.
DO $$
DECLARE prepare_body text; capture_body text; form_body text; finish_body text; save_body text; delete_body text;
BEGIN
 SELECT prosrc INTO prepare_body FROM pg_proc WHERE oid='public.prepare_meta_purchase_delivery(bigint,uuid)'::regprocedure;
 SELECT prosrc INTO capture_body FROM pg_proc WHERE oid='public.capture_meta_purchase_consent_internal(bigint,jsonb)'::regprocedure;
 SELECT prosrc INTO form_body FROM pg_proc WHERE oid='public.set_form_meta_purchase(bigint,bigint,boolean)'::regprocedure;
 SELECT prosrc INTO finish_body FROM pg_proc WHERE oid='public.finish_meta_purchase_delivery(bigint,uuid,text)'::regprocedure;
 SELECT prosrc INTO save_body FROM pg_proc WHERE oid='public.save_unit_meta_purchase(bigint,text,text,text,boolean,text)'::regprocedure;
 SELECT prosrc INTO delete_body FROM pg_proc WHERE oid='public.delete_unit_meta_purchase(bigint)'::regprocedure;
 PERFORM assert_true(prepare_body LIKE '%WHERE unit=connector_unit FOR NO KEY UPDATE%',
  'prepare acquires the final write-compatible connector lock before credential pause, without a shared-lock upgrade');
 PERFORM assert_true(capture_body LIKE '%FOR KEY SHARE OF c SKIP LOCKED%',
  'capture coexists with routine non-key writes and skips disconnect/key-change locks');
 PERFORM assert_true(form_body LIKE '%analytics.meta_purchase_connectors WHERE unit=p_unit FOR NO KEY UPDATE%',
  'form selection writes serialize with the connector lock held throughout prepare');
 PERFORM assert_true(finish_body LIKE '%analytics.meta_purchase_connectors WHERE unit=connector_unit FOR NO KEY UPDATE%'
  AND save_body LIKE '%analytics.meta_purchase_connectors WHERE unit=p_unit FOR NO KEY UPDATE%',
  'all routine writers share the non-key-update lock protocol, compatible with capture key-share');
 PERFORM assert_true(delete_body LIKE '%analytics.meta_purchase_connectors WHERE unit=p_unit FOR UPDATE%'
  AND delete_body LIKE '%DELETE FROM analytics.meta_purchase_connectors WHERE unit=p_unit%',
  'disconnect retains the exclusive row fence that key-share capture cannot cross');
END $$;

-- Overview remains organizer-admin scoped; worker payloads and retention stay private.
DO $$
DECLARE role_name text; signature text;
BEGIN
 PERFORM assert_true(has_function_privilege('authenticated','public.get_unit_meta_purchase(bigint)','EXECUTE'),'authenticated overview retains its internal permission check');
 PERFORM assert_false(has_function_privilege('anon','public.get_unit_meta_purchase(bigint)','EXECUTE'),'anonymous overview remains forbidden');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  FOREACH signature IN ARRAY ARRAY['public.claim_meta_purchase_deliveries(integer)','public.prepare_meta_purchase_delivery(bigint,uuid)','public.finish_meta_purchase_delivery(bigint,uuid,text)'] LOOP
   PERFORM assert_false(has_function_privilege(role_name,signature,'EXECUTE'),'worker remains service-only: '||signature);
   PERFORM assert_true(has_function_privilege('service_role',signature,'EXECUTE'),'service worker remains authorized: '||signature);
  END LOOP;
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM assert_false(has_function_privilege(role_name,'public.purge_meta_purchase_data_internal()','EXECUTE'),'retention remains operator-only');
 END LOOP;
END $$;
