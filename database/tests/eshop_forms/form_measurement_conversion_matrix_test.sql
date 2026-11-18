-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); fid bigint:=(x->>'form')::bigint; command uuid:=gen_random_uuid(); client uuid:=gen_random_uuid();
 payload jsonb; result jsonb; replay jsonb; oid bigint; conversion jsonb; unauthorized boolean:=false;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 UPDATE eshop.products SET price=0,currency_code='EUR' WHERE id=(x->>'product')::bigint;
 UPDATE forms SET data=coalesce(data,'{}')||'{"analytics":{"enabled":false}}' WHERE id=fid;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES((x->>'organization')::bigint,true,1,'fixture','conversion matrix');
 payload:=pg_temp.checkout(x)||'{"analytics":{"enabled":true,"organization_allowed":true}}'::jsonb;
 result:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','free registration succeeds while disabled');
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_true(result#>'{data,analytics}' IS NULL OR result#>'{data,analytics}'='null','client-supplied analytics cannot turn on stored policy');
 PERFORM assert_eq((SELECT count(*) FROM analytics.conversion_facts WHERE "order"=oid),0::bigint,'no facts captured for a disabled form');
 UPDATE forms SET data=coalesce(data,'{}')||'{"analytics":{"enabled":true}}' WHERE id=fid;
 replay:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_true(replay#>'{data,analytics}' IS NULL OR replay#>'{data,analytics}'='null','later enable cannot backfill old receipt');
 command:=gen_random_uuid();
 UPDATE analytics.organization_policy SET enabled=false,revision=2 WHERE organization=(x->>'organization')::bigint;
 result:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','policy denial does not break checkout');
 PERFORM assert_true(result#>'{data,analytics}' IS NULL OR result#>'{data,analytics}'='null','organization denial blocks facts');
 UPDATE analytics.organization_policy SET enabled=true,revision=3 WHERE organization=(x->>'organization')::bigint;
 replay:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_true(replay#>'{data,analytics}' IS NULL OR replay#>'{data,analytics}'='null','later platform permission cannot backfill old receipt');
 command:=gen_random_uuid();result:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','allowed free registration succeeds');
 conversion:=result#>'{data,analytics}';oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_eq(conversion->>'event','generate_lead','free registration has server-owned lead event');
 PERFORM assert_eq(conversion->>'currency','EUR','free registration keeps actual EUR currency');
 PERFORM assert_eq(conversion->>'lead_source','free_registration','free registration distinguished from waitlist');
 PERFORM assert_true((conversion->>'event_id')::uuid IS NOT NULL,'stable non-capability UUID');
 PERFORM assert_eq(create_ticket_order_client_sync_v1(payload,command,client)#>'{data,analytics}',conversion,'free registration replay identity stable');
 UPDATE forms SET data=coalesce(data,'{}')||'{"analytics":{"enabled":false}}' WHERE id=fid;
 PERFORM assert_true(create_ticket_order_client_sync_v1(payload,command,client)#>'{data,analytics}'='null','form-level revocation also filters replay');
 UPDATE forms SET data=coalesce(data,'{}')||'{"analytics":{"enabled":true}}' WHERE id=fid;
 PERFORM assert_eq(create_ticket_order_client_sync_v1(payload,command,client)#>'{data,analytics}',conversion,'re-enabled authorized replay retains original facts');
 BEGIN
  replay:=create_ticket_order_client_sync_v1(payload,command,gen_random_uuid());
  unauthorized:=coalesce((replay->>'code')::integer,200)<>200;
 EXCEPTION WHEN invalid_parameter_value OR insufficient_privilege THEN unauthorized:=true; END;
 PERFORM assert_true(unauthorized,'different client cannot recover somebody else''s conversion');
 PERFORM assert_eq((SELECT count(*) FROM analytics.conversion_facts WHERE "order"=oid),1::bigint,'one immutable free-registration fact despite retries');
 -- Inject a real SQL persistence failure in measurement only. The caller must
 -- still receive its committed order/payment/receipt without any analytics.
 ALTER TABLE analytics.conversion_facts ADD CONSTRAINT measurement_fixture_fault CHECK(payload->>'event'<>'generate_lead') NOT VALID;
 command:=gen_random_uuid();result:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','analytics persistence failure cannot roll back checkout');
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND price=0),'free registration survives measurement error');
 PERFORM assert_eq((SELECT count(*) FROM analytics.conversion_facts WHERE "order"=oid),0::bigint,'failed fact remains absent');
 ALTER TABLE analytics.conversion_facts DROP CONSTRAINT measurement_fixture_fault;
 replay:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'receipt is durable despite analytics error');
 PERFORM assert_true(replay#>'{data,analytics}'='null','replay never synthesizes facts after a failed capture');
END $$;

-- Signed-in visitors receive the same conversion projection as anonymous buyers; staff remains excluded.
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); result jsonb; oid bigint; command uuid:=gen_random_uuid(); client uuid:=gen_random_uuid(); identity text;
BEGIN
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES((x->>'organization')::bigint,true,1,'fixture','signed-in visitor purchase');
 UPDATE public.forms SET data=coalesce(data,'{}')||'{"analytics":{"enabled":true,"purchase_timing":"paid"}}' WHERE id=(x->>'form')::bigint;
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 PERFORM assert_eq(public.form_measurement_visitor_role_internal((x->>'form')::bigint),'visitor','signed-in fixture is a customer, not unit staff');
 result:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x),command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','signed-in visitor checkout succeeds');
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_true(EXISTS(SELECT FROM analytics.conversion_facts WHERE "order"=oid AND kind='purchase'),'signed-in visitor records immutable purchase snapshot');
 PERFORM assert_eq(public.form_order_purchase_timing_internal(oid),'paid','signed-in visitor snapshot retains selected timing');
 PERFORM assert_true(result#>'{data,analytics}' IS NULL OR result#>'{data,analytics}'='null','signed-in paid response waits for payment');
 UPDATE public.forms SET data=jsonb_set(data,'{analytics,purchase_timing}','"order"') WHERE id=(x->>'form')::bigint;
 command:=gen_random_uuid();
 result:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||'{"email":"signed-in-order@example.invalid"}',command,client);
 PERFORM assert_eq(result#>>'{data,analytics,event}','purchase','signed-in order-mode visitor gets Purchase');
 identity:=result#>>'{data,analytics,event_id}';
 PERFORM assert_eq(public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||'{"email":"signed-in-order@example.invalid"}',command,client)#>>'{data,analytics,event_id}',identity,'signed-in replay retains Purchase UUID');
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES((x->>'unit')::bigint,(x->>'actor')::uuid,true) ON CONFLICT(unit,"user") DO UPDATE SET is_manager=true;
 PERFORM assert_eq(public.form_measurement_visitor_role_internal((x->>'form')::bigint),'staff','unit manager is staff');
 result:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x)||'{"email":"signed-in-order@example.invalid"}',command,client);
 PERFORM assert_true(result#>'{data,analytics}' IS NULL OR result#>'{data,analytics}'='null','staff replay receives no Purchase');
END $$;
