-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); fid bigint:=(x->>'form')::bigint; command uuid:=gen_random_uuid(); client uuid:=gen_random_uuid();
 payload jsonb; result jsonb; replay jsonb; oid bigint; conversion jsonb; unauthorized boolean:=false;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 UPDATE eshop.products SET price=0,currency_code='EUR' WHERE id=(x->>'product')::bigint;
 UPDATE forms SET data='{"analytics":{"enabled":false}}' WHERE id=fid;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES((x->>'organization')::bigint,true,1,'fixture','conversion matrix');
 payload:=pg_temp.checkout(x)||'{"analytics":{"enabled":true,"organization_allowed":true}}'::jsonb;
 result:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','free registration succeeds while disabled');
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_true(result#>'{data,analytics}' IS NULL OR result#>'{data,analytics}'='null','client-supplied analytics cannot turn on stored policy');
 PERFORM assert_eq((SELECT count(*) FROM analytics.conversion_facts WHERE "order"=oid),0::bigint,'no facts captured for a disabled form');
 UPDATE forms SET data='{"analytics":{"enabled":true}}' WHERE id=fid;
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
 UPDATE forms SET data='{"analytics":{"enabled":false}}' WHERE id=fid;
 PERFORM assert_true(create_ticket_order_client_sync_v1(payload,command,client)#>'{data,analytics}'='null','form-level revocation also filters replay');
 UPDATE forms SET data='{"analytics":{"enabled":true}}' WHERE id=fid;
 PERFORM assert_eq(create_ticket_order_client_sync_v1(payload,command,client)#>'{data,analytics}',conversion,'re-enabled authorized replay retains original facts');
 BEGIN
  replay:=create_ticket_order_client_sync_v1(payload,command,gen_random_uuid());
  unauthorized:=coalesce((replay->>'code')::integer,200)<>200;
 EXCEPTION WHEN invalid_parameter_value OR insufficient_privilege THEN unauthorized:=true; END;
 PERFORM assert_true(unauthorized,'different client cannot recover somebody else''s conversion');
 PERFORM assert_eq((SELECT count(*) FROM analytics.conversion_facts WHERE "order"=oid),1::bigint,'one immutable free-registration fact despite retries');
 -- Multiple confirmed admissions retain the finalizer's exact cent amounts.
 UPDATE eshop.products SET price=0.10 WHERE id=(x->>'product')::bigint;
 UPDATE eshop.bank_accounts SET supported_currencies=ARRAY['EUR'],account_number='DE89370400440532013000' WHERE id IN
  (SELECT bank_account FROM eshop.unit_bank_accounts WHERE unit=(x->>'unit')::bigint);
 payload:=pg_temp.checkout(x);
 payload:=jsonb_set(payload,'{ticket}',jsonb_build_array(payload->'ticket'->0,payload->'ticket'->0,payload->'ticket'->0));
 command:=gen_random_uuid();result:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','three paid EUR admissions succeed: '||result::text);
 conversion:=result#>'{data,analytics}';
 PERFORM assert_eq(conversion->>'event','purchase','bank order uses purchase');
 PERFORM assert_eq(conversion#>>'{ecommerce,payment_type}','bank_transfer','bank order keeps payment channel');
 PERFORM assert_eq((conversion#>>'{ecommerce,value}')::numeric,0.30::numeric,'integer cents survive repeated product quantities');
 PERFORM assert_eq((conversion#>>'{ecommerce,items,0,quantity}')::integer,3,'three admissions aggregate to quantity three');
 PERFORM assert_eq((conversion#>>'{ecommerce,items,0,price}')::numeric,0.10::numeric,'snapshot preserves charged unit price');
 PERFORM assert_eq(conversion#>>'{ecommerce,items,0,item_category}','spot','item category comes from the charged product type snapshot');
 PERFORM assert_eq(conversion#>>'{ecommerce,items,0,item_brand}','Waitlist regression','item brand is the occasion title');
 PERFORM assert_eq(jsonb_array_length(conversion#>'{ecommerce,items}'),1,'labels do not split a charged line');
 -- A snapshot without the optional label keeps the same value and omits only that field.
 oid:=(result#>>'{data,order,id}')::bigint;
 UPDATE eshop.orders o SET data=jsonb_set(o.data,'{tickets}',(SELECT jsonb_agg(jsonb_set(t,'{products}',(SELECT jsonb_agg(p-'type_title') FROM jsonb_array_elements(t->'products') p)))
  FROM jsonb_array_elements(o.data->'tickets') t)) WHERE o.id=oid;
 DELETE FROM analytics.conversion_facts WHERE "order"=oid;
 PERFORM public.record_form_conversion_internal(oid);
 PERFORM assert_false((SELECT cf.payload#>'{ecommerce,items,0}' ? 'item_category' FROM analytics.conversion_facts cf WHERE "order"=oid),'missing product type label is omitted, not invented');
 PERFORM assert_eq((SELECT (cf.payload#>>'{ecommerce,value}')::numeric FROM analytics.conversion_facts cf WHERE "order"=oid),0.30::numeric,'missing label cannot change the charged total');
 -- Inject a real SQL persistence failure in measurement only. The caller must
 -- still receive its committed order/payment/receipt without any analytics.
 ALTER TABLE analytics.conversion_facts ADD CONSTRAINT measurement_fixture_fault CHECK(payload->>'event'<>'purchase') NOT VALID;
 command:=gen_random_uuid();result:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','analytics persistence failure cannot roll back checkout');
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND price=0.30),'canonical paid-price order survives measurement error');
 PERFORM assert_eq((SELECT count(*) FROM analytics.conversion_facts WHERE "order"=oid),0::bigint,'failed fact remains absent');
 ALTER TABLE analytics.conversion_facts DROP CONSTRAINT measurement_fixture_fault;
 replay:=create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'receipt is durable despite analytics error');
 PERFORM assert_true(replay#>'{data,analytics}'='null','replay never synthesizes facts after a failed capture');
END $$;
