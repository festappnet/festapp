-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint;
 org bigint:=(x->>'organization')::bigint; snapshot jsonb; b analytics.website_consent_bindings; bad jsonb;
BEGIN
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=org;
 UPDATE public.units SET data=data||'{"measurement_consent_bridge":true,"measurement_websites":["https://tickets.example"]}' WHERE id=un;
 INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled)
 VALUES(un,'123456',gen_random_uuid(),'https://tickets.example',true);
 snapshot:=jsonb_build_object('source','klaro','timestamp',to_char(statement_timestamp()-interval '1 second','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal(un)->>'consentRevision',
  'ad_storage',true,'ad_user_data',true,'ad_personalization',true);
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot),'scoped saved standalone choice');
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot-'source') IS FALSE,'missing source returns false, never SQL NULL');
 UPDATE public.organizations SET data=data-'DEFAULT_URL' WHERE id=org;
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot) IS FALSE,'missing standalone service URL returns false, never SQL NULL');
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=org;
 FOREACH bad IN ARRAY ARRAY['null'::jsonb,'{}'::jsonb,snapshot||'{"ad_user_data":false}',snapshot||'{"ad_personalization":false}',
  snapshot||'{"ad_storage":false}',snapshot||'{"source":"invented"}',snapshot||'{"timestamp":"2026-99-99T00:00:00.000Z"}',
  snapshot||'{"consentRevision":"obsolete"}',snapshot||'{"websiteOrigin":"https://attacker.example"}',
  snapshot||'{"timestamp":"2000-01-01T00:00:00.000Z"}'] LOOP
  PERFORM assert_false(public.meta_purchase_snapshot_valid_internal(un,bad),'malformed, denied, stale or unbound choice fails closed');
 END LOOP;
 INSERT INTO analytics.website_consent_bindings(unit,website_origin,platform,provider_config,version,enabled,confirmed_revision,confirmed_at)
 VALUES(un,'https://tickets.example','html','{"provider":"cookiebot"}',1,true,snapshot->>'consentRevision',clock_timestamp()-interval '1 minute') RETURNING * INTO b;
 snapshot:=snapshot||jsonb_build_object('source','cookiebot','binding',jsonb_build_object('id',b.id,'version',b.version));
 PERFORM assert_true(public.meta_purchase_snapshot_valid_internal(un,snapshot),'managed choice uses live exact binding');
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
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint; fid bigint:=(x->>'form')::bigint;
 snapshot jsonb; checkout jsonb; receipt jsonb; replay jsonb; oid bigint; b analytics.website_consent_bindings; claimed uuid:=gen_random_uuid();
 command_id uuid:=gen_random_uuid(); client_id uuid:=gen_random_uuid();
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
 snapshot:=jsonb_build_object('source','cookiebot','timestamp',to_char(statement_timestamp()-interval '1 second','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
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
 PERFORM assert_eq((SELECT fbp FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'fb.1.1795000000000.1234','matching is captured with this exact order');
 PERFORM assert_eq((SELECT host(client_ip) FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'2001:db8::1','trusted checkout header supplies the address');
 PERFORM assert_false(receipt::text LIKE '%fb.1.%' OR receipt::text LIKE '%2001:db8%','matching never enters the browser receipt');
 replay:=public.create_ticket_order_client_sync_v1(
  jsonb_set(checkout,'{metaPurchaseConsent,matching,fbc}','"fb.1.1795000001000.Click_123"'),command_id,client_id);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'reload with changed matching replays the first order');
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
 PERFORM assert_true((SELECT status='expired' AND consent_snapshot IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'retention expiry erases snapshot');
 UPDATE analytics.meta_purchase_deliveries SET phone_hash=repeat('b',64),fbp='fb.1.1795000000000.1234',fbc='fb.1.1795000000000.Click_123',client_ip='192.0.2.1',status='pending',consent_snapshot=snapshot,lease=claimed,prepared=true WHERE order_id=oid;
 PERFORM assert_true(public.finish_meta_purchase_delivery(oid,claimed,'sent'),'receipt is finalized');
 PERFORM assert_true((SELECT status='sent' AND consent_snapshot IS NULL AND phone_hash IS NULL AND fbp IS NULL AND fbc IS NULL AND client_ip IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'sent receipts contain no snapshot');
 PERFORM public.issue_order_overview_internal(oid,pg_temp.delivery('fixture',repeat('c',64),oid),gen_random_uuid());
 PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot||'{"ad_storage":false}'),
  'a denial at the captured decision time cannot withdraw');
 snapshot:=snapshot||jsonb_build_object('timestamp',to_char(statement_timestamp()-interval '500 milliseconds','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'ad_storage',false);
 PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot||'{"websiteOrigin":"https://other.example"}'),
  'another website cannot withdraw captured consent');
 PERFORM assert_false(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot||'{"ad_storage":null}'),
  'an unknown purpose cannot withdraw captured consent');
 PERFORM assert_true(public.revoke_meta_purchase_consent(repeat('c',64),oid,snapshot),
  'a later denial on the same site withdraws even after its sent snapshot was scrubbed');
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
 mode text; receipt jsonb; oid bigint; snapshot jsonb; payment_id bigint; transaction_id bigint;
 paid_event uuid; order_event uuid; claimed uuid; prepared jsonb; order_data jsonb;
BEGIN
 FOREACH mode IN ARRAY ARRAY['order','legacy','missing','paid_without_capi','legacy_capi_flag','paid','no_browser_items','waitlist_acceptance'] LOOP
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
  UPDATE analytics.meta_purchase_connectors SET enabled=(mode IN ('paid','legacy_capi_flag','no_browser_items','waitlist_acceptance')) WHERE unit=un;
  receipt:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||jsonb_build_object('email','consent-'||mode||'-'||un::text||'@example.invalid'),gen_random_uuid(),gen_random_uuid());
  PERFORM assert_eq(receipt#>>'{data,code}','200','cohort fixture checkout succeeds');
  oid:=(receipt#>>'{data,order,id}')::bigint;
  IF mode IN ('no_browser_items','waitlist_acceptance') THEN
   DELETE FROM analytics.conversion_facts WHERE "order"=oid AND kind='purchase';
   IF mode='no_browser_items' THEN
    SELECT data INTO order_data FROM eshop.orders WHERE id=oid;
    UPDATE eshop.orders SET data=jsonb_set(data,'{tickets}','[]'::jsonb) WHERE id=oid;
    PERFORM public.record_form_conversion_internal(oid);
    UPDATE eshop.orders SET data=order_data WHERE id=oid;
    PERFORM assert_true(public.form_purchase_datalayer_internal(oid) IS NULL,'no browser item payload is exported');
   ELSE
    PERFORM public.record_form_conversion_internal(oid,false);
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
  PERFORM assert_eq(public.form_purchase_timing_internal(fid),'paid','current CAPI setting requests paid');
  IF mode IN ('order','legacy') THEN
   PERFORM assert_eq(public.form_order_purchase_timing_internal(oid),'order','old order cohort remains order after enablement');
  ELSIF mode='paid_without_capi' THEN
   PERFORM assert_eq(public.form_order_purchase_timing_internal(oid),'paid','paid-only browser cohort is frozen before CAPI enablement');
  ELSIF mode='missing' THEN
   PERFORM assert_true(public.form_order_purchase_timing_internal(oid) IS NULL,'missing snapshot confers no paid cohort');
  END IF;
  PERFORM assert_true(public.form_order_purchase_capi_required_internal(oid) IS NOT DISTINCT FROM (mode IN ('paid','no_browser_items')),
   'CAPI is required only when frozen at creation, missing flag fails closed');
  snapshot:=jsonb_build_object('source','klaro','timestamp',to_char(statement_timestamp()-interval '1 second','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal(un)->>'consentRevision',
   'revision',public.get_meta_purchase_consent(x->>'link')->>'revision','userAgent','Cohort regression',
   'ad_storage',true,'ad_user_data',true,'ad_personalization',true);
  UPDATE eshop.orders SET data=data||'{"phone":"+420 777 123 456"}' WHERE id=oid;
  PERFORM public.capture_meta_purchase_consent_internal(oid,snapshot||'{"matching":{"fbp":"fb.1.1795000000000.1234","fbc":"invalid"}}');
  PERFORM assert_eq((SELECT phone_hash FROM analytics.meta_purchase_deliveries WHERE order_id=oid),encode(extensions.digest('420777123456','sha256'),'hex'),'hash uses country code and digits only');
  PERFORM assert_true(EXISTS(SELECT FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'captured pending delivery exists before payment');
  SELECT payment_info INTO STRICT payment_id FROM eshop.orders WHERE id=oid;
  INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
  SELECT bank_account,100,'CZK',now(),'fio_api' FROM eshop.payment_info WHERE id=payment_id RETURNING id INTO transaction_id;
  PERFORM public.apply_transaction_pairing(transaction_id,payment_id,'manual_attach','user');
  SELECT event_id INTO STRICT paid_event FROM analytics.conversion_facts WHERE "order"=oid AND kind='order_fully_paid';
  PERFORM assert_true(paid_event<>order_event,'paid fact already exists with a distinct event UUID');
  PERFORM assert_true(public.form_paid_conversion_eligible_internal(oid),'payment and live policy qualify independently of cohort');
  IF mode NOT IN ('paid','no_browser_items') THEN
   PERFORM assert_false(EXISTS(SELECT FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid),
    'order/legacy/missing/non-CAPI-paid cohort is never claimed despite captured paid fact');
   -- Simulate an older worker claim: prepare must independently fence it.
   claimed:=gen_random_uuid();
   UPDATE analytics.meta_purchase_deliveries SET phone_hash=repeat('b',64),lease=claimed,lease_until=clock_timestamp()+interval '1 minute' WHERE order_id=oid;
   PERFORM assert_true(public.prepare_meta_purchase_delivery(oid,claimed) IS NULL,'order/legacy/missing/non-CAPI-paid cohort is never prepared');
   PERFORM assert_true((SELECT status='invalid' AND attempts=0 AND consent_snapshot IS NULL
    FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'cohort rejection discloses no send payload and scrubs metadata');
  ELSE
   SELECT d.lease INTO STRICT claimed FROM public.claim_meta_purchase_deliveries(20) d WHERE d.order_id=oid;
   prepared:=public.prepare_meta_purchase_delivery(oid,claimed);
   PERFORM assert_eq(prepared->>'phoneHash',encode(extensions.digest('420777123456','sha256'),'hex'),'prepared payload carries phone hash');
   PERFORM assert_eq(prepared->>'fbp','fb.1.1795000000000.1234','prepared payload carries validated browser identifier');
   PERFORM assert_true(prepared->>'fbc' IS NULL,'malformed browser identifier is omitted');
   PERFORM assert_eq(prepared->>'eventId',paid_event::text,'paid cohort still prepares the original paid fact');
   UPDATE analytics.meta_purchase_deliveries SET prepared=false,client_ip='192.0.2.1',consent_at=clock_timestamp()-interval '8 days' WHERE order_id=oid;
   prepared:=public.prepare_meta_purchase_delivery(oid,claimed);
   PERFORM assert_true(prepared IS NOT NULL AND prepared->>'clientIp' IS NULL,'prepare independently suppresses expired raw addresses');
   PERFORM assert_true((SELECT client_ip IS NULL FROM analytics.meta_purchase_deliveries WHERE order_id=oid),'prepare scrubs expired raw address');
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
