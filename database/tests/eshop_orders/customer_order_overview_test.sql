-- Transaction-local fixtures. All email envelopes are sealed test doubles; no provider is invoked.
BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
CREATE FUNCTION pg_temp.fixture(cap integer DEFAULT 1) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; un bigint; oc bigint; f bigint; fk uuid; pt bigint; prod bigint; bank bigint; actor uuid; suffix text:=gen_random_uuid()::text;
BEGIN
 INSERT INTO organizations(title) VALUES('Waitlist regression '||suffix) RETURNING id INTO org;
 INSERT INTO units(title,organization) VALUES('Waitlist regression',org) RETURNING id INTO un;
 INSERT INTO occasions(title,unit,organization,link,start_time,end_time) VALUES('Waitlist regression',un,org,suffix,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO forms(occasion,link,participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds) VALUES(oc,suffix,cap,cap IS NOT NULL,CASE WHEN cap IS NOT NULL THEN 3600 END) RETURNING id,key INTO f,fk;
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Regression bank','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('spot','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion) VALUES('Admission',pt,100,'CZK',oc) RETURNING id INTO prod;
 INSERT INTO form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 SELECT id INTO actor FROM auth.users ORDER BY id LIMIT 1;
 IF actor IS NULL THEN RAISE EXCEPTION 'Bootstrap auth user required'; END IF;
 INSERT INTO occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor) VALUES(oc,actor,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 RETURN jsonb_build_object('organization',org,'unit',un,'occasion',oc,'form',f,'key',fk,'type',pt,'product',prod,'actor',actor,'link',suffix);
END $$;
CREATE FUNCTION pg_temp.checkout(x jsonb,tickets bigint[] DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',
 CASE WHEN tickets IS NULL THEN jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))
 ELSE (SELECT jsonb_agg(jsonb_build_object('ticketId',id,'fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))) FROM unnest(tickets) id) END);
$$;
CREATE FUNCTION pg_temp.delivery(code text,token text,oid bigint DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('orderId',oid,'recipient','regression@example.invalid','templateCode',code,
 'tokenHash',encode(extensions.digest(token,'sha256'),'hex'),'contentHash',repeat('f',64),'sealed',jsonb_build_object('ciphertext','sealed-test-double'));
$$;
CREATE FUNCTION pg_temp.register(x jsonb,n integer,token text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; payload jsonb;
BEGIN
 payload:=jsonb_build_object('form',x->'key','email','regression@example.invalid','tickets',(SELECT jsonb_agg(jsonb_build_object('fields','[]'::jsonb)) FROM generate_series(1,n)));
 r:=public.execute_waitlist_command_client_sync_v1('register',payload,gen_random_uuid(),gen_random_uuid(),NULL,jsonb_build_array(pg_temp.delivery('waitlist_confirmation',coalesce(token,encode(extensions.gen_random_bytes(32),'hex')))));
 IF r#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Register failed %',r; END IF;
 RETURN jsonb_build_object('order',(r#>>'{data,order,id}')::bigint,'response',r,'payload',payload);
END $$;
CREATE FUNCTION pg_temp.offer(x jsonb,oid bigint,n integer,token text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; proposal jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 proposal:=public.get_waitlist_offer_proposal((x->>'form')::bigint);
 r:=public.execute_waitlist_command_client_sync_v1('send',jsonb_build_object('formId',x->'form','revision',proposal->'revision','expiresAt',clock_timestamp()+interval '1 hour','recipients',jsonb_build_array(jsonb_build_object('orderId',oid,'count',n))),gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid,jsonb_build_array(pg_temp.delivery('waitlist_offer',coalesce(token,encode(extensions.gen_random_bytes(32),'hex')),oid)));
 IF r#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Offer failed %',r; END IF;
 RETURN jsonb_build_object('id',r#>>'{data,offers,0,offerId}','response',r);
END $$;
CREATE FUNCTION pg_temp.accept(x jsonb,w jsonb,tickets bigint[],command uuid DEFAULT gen_random_uuid(),token text DEFAULT NULL,actor uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','ticketIds',to_jsonb(tickets),'token',token,'orderDetails',pg_temp.checkout(x,tickets)),command,'ac000000-0000-0000-0000-000000000001'::uuid,coalesce(actor,(x->>'actor')::uuid));
$$;
-- Read-only test convenience view: every identity, answer and owner comes from
-- existing tickets/OPT/orders. Lifecycle is the public server projection.
CREATE VIEW pg_temp.ticket_rows AS
 SELECT t.*,o.id current_order_id,o.form form_id,coalesce(o.source_waitlist_order_id,o.id) origin_order_id,
 t.data answers,t.waitlist_queue_at queue_at,t.id ticket_id,
 public.get_effective_waitlist_ticket_lifecycle_internal(t.id) lifecycle
 FROM eshop.tickets t JOIN (SELECT DISTINCT "order",ticket FROM eshop.order_product_ticket) link ON link.ticket=t.id
 JOIN eshop.orders o ON o.id=link."order";
CREATE FUNCTION pg_temp.ticket_ids(p_order bigint) RETURNS bigint[] LANGUAGE sql AS $$
 SELECT coalesce(array_agg(DISTINCT ticket ORDER BY ticket),'{}'::bigint[]) FROM eshop.order_product_ticket WHERE "order"=p_order;
$$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(2); y jsonb:=pg_temp.fixture(1); r jsonb; oid bigint; regular bigint; other bigint;
 ids bigint[]; w jsonb; child bigint; view_token text:=repeat('a',64); manage text:=repeat('b',64); offer_token text:=repeat('c',64);
 delivery jsonb:=jsonb_build_object('tokenHash',encode(extensions.digest(view_token,'sha256'),'hex'),'sealed',jsonb_build_object('ciphertext','synthetic'),'contentHash',repeat('f',64));
 pid bigint; status text; raw text; source jsonb; replay jsonb; command uuid:=gen_random_uuid();
BEGIN
 FOR i IN 1..2 LOOP r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); END LOOP;
 oid:=(pg_temp.register(x,2,manage)->>'order')::bigint;
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(y));
 other:=(pg_temp.register(y,1)->>'order')::bigint;
 ids:=pg_temp.ticket_ids(oid);
 PERFORM set_config('request.jwt.claim.sub','',true);
 source:=public.resolve_customer_order_access_v1(manage,oid,NULL,command,delivery);
 replay:=public.resolve_customer_order_access_v1(manage,oid,NULL,gen_random_uuid(),delivery);
 PERFORM assert_eq(source->'source',replay->'source','bootstrap converges to existing encrypted source');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash) WHERE c.order_id=oid),1::bigint,'single generation');
 PERFORM assert_true(NOT source::text LIKE '%'||view_token||'%','resolver SQL contains no raw token');
 r:=public.get_customer_order_overview(view_token,oid);
 PERFORM assert_eq(r->>'code','200'::text,'view available while waiting');
 PERFORM assert_eq(jsonb_array_length(r->'orders'),0,'waiting is not free order');
 PERFORM assert_eq(jsonb_array_length(r->'people'),2,'two stable tickets');
 PERFORM assert_eq(public.get_customer_order_overview(view_token,other)->>'code','403'::text,'wrong root and tenant denied');
 PERFORM assert_eq(public.get_customer_order_overview(manage,oid)->>'code','403'::text,'manage is not view');
 PERFORM assert_eq(public.get_customer_order_overview(repeat('d',64),oid)->>'code','403'::text,'invalid token');
 FOR regular IN SELECT id FROM eshop.orders WHERE form=(x->>'form')::bigint AND state<>'waitlisted' LOOP
  PERFORM public.update_order_and_tickets_to_storno_221(regular); END LOOP;
 w:=pg_temp.offer(x,oid,2,offer_token);
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.check_waitlist_scope_internal(oid,(w->>'id')::uuid,view_token,NULL,'accept'); RAISE EXCEPTION 'view accepted write'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='view accepted write' THEN RAISE; END IF; END;
 BEGIN PERFORM public.check_waitlist_scope_internal(oid,NULL,view_token,NULL,'withdraw'); RAISE EXCEPTION 'view accepted withdraw'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='view accepted withdraw' THEN RAISE; END IF; END;
 r:=pg_temp.accept(x,w,ARRAY[ids[2]],gen_random_uuid(),offer_token);
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'partial acceptance'); child:=(r#>>'{data,order,id}')::bigint;
 r:=public.get_customer_order_overview(view_token,oid);
 PERFORM assert_eq(jsonb_array_length(r->'orders'),1,'partial child included');
 PERFORM assert_eq((r#>>'{orders,0,id}')::bigint,child,'correct child');
 PERFORM assert_eq(jsonb_array_length(r#>'{orders,0,items}'),1,'stored item projection');
 PERFORM assert_eq(public.get_customer_order_overview(view_token,child)->>'code','403'::text,'child cannot select scope');
 r:=pg_temp.accept(x,w,ARRAY[ids[1]],gen_random_uuid(),offer_token);
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'remaining in-place acceptance');
 r:=public.get_customer_order_overview(view_token,oid);
 PERFORM assert_eq(jsonb_array_length(r->'orders'),2,'two distinct payments');
 PERFORM assert_eq(jsonb_array_length(r->'people'),2,'no duplicate people');
 PERFORM assert_true(NOT r::text LIKE '%ticket_symbol%' AND NOT r ? 'data' AND NOT r ? 'allowedActions','allowlist only');
 BEGIN PERFORM public.resolve_customer_order_access_v1(offer_token,oid,(w->>'id')::uuid,gen_random_uuid(),delivery); RAISE EXCEPTION 'terminal bootstrap'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='terminal bootstrap' THEN RAISE; END IF; END;
 BEGIN PERFORM public.resolve_customer_order_access_v1(manage,oid,NULL,gen_random_uuid(),delivery); RAISE EXCEPTION 'completed manage bootstrap'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='completed manage bootstrap' THEN RAISE; END IF; END;
 SELECT payment_info INTO pid FROM eshop.orders WHERE id=child;
 UPDATE eshop.bank_accounts SET account_number='CZ6508000000192000145399' WHERE id=(SELECT bank_account FROM eshop.payment_info WHERE id=pid);
 UPDATE eshop.payment_info SET amount=1000,deposit_amount=300,paid=300,deposit_deadline=now()-interval '1 day',deadline=now()+interval '1 day' WHERE id=pid;
 UPDATE eshop.orders SET state='paid',price=1000 WHERE id=child;
 r:=public.customer_order_payment_internal(child);
 PERFORM assert_eq(r->>'status','deposit_paid'::text,'paid order is only deposit paid');
 PERFORM assert_eq((r->>'dueNow')::numeric,700::numeric,'remaining deposit balance');
 FOR status IN SELECT unnest(ARRAY['unpaid','partially_paid','deposit_paid','fully_paid','fully_paid']) LOOP
  UPDATE eshop.payment_info SET paid=CASE status WHEN 'unpaid' THEN 0 WHEN 'partially_paid' THEN 100 WHEN 'deposit_paid' THEN 300 ELSE 1000 END WHERE id=pid;
  UPDATE eshop.orders SET state='ordered' WHERE id=child;
  PERFORM assert_eq(public.customer_order_payment_internal(child)->>'status',status,'payment matrix');
 END LOOP;
 UPDATE eshop.payment_info SET paid=0 WHERE id=pid;
 r:=public.customer_order_payment_internal(child);
 PERFORM assert_eq(r->>'overdue','true'::text,'unpaid deposit overdue');
 PERFORM assert_eq((r->>'dueNow')::numeric,300::numeric,'deposit due first');
 UPDATE eshop.payment_info SET currency_code='EUR',creditor_reference=public.generate_creditor_reference(variable_symbol) WHERE id=pid;
 UPDATE eshop.orders SET currency_code='EUR' WHERE id=child;
 r:=public.customer_order_payment_internal(child);
 PERFORM assert_eq(r->>'referenceKind','RF'::text,'EUR uses RF');
 PERFORM assert_eq(r->>'reference',(SELECT creditor_reference FROM eshop.payment_info WHERE id=pid),'existing reference fact');
 UPDATE eshop.payment_info SET currency_code='CZK' WHERE id=pid;
 PERFORM assert_eq(public.customer_order_payment_internal(child)->>'status','unknown'::text,'currency mismatch is unknown');
 UPDATE eshop.orders SET currency_code='CZK' WHERE id=child;
 UPDATE eshop.payment_info SET paid=1200,returned=100 WHERE id=pid;
 r:=public.customer_order_payment_internal(child);
 PERFORM assert_eq((r->>'overpaid')::numeric,200::numeric,'overpayment');
 PERFORM assert_eq((r->>'returned')::numeric,100::numeric,'returned independent');
 PERFORM assert_eq((r->>'totalOutstanding')::numeric,0::numeric,'refund is not another demand');
 UPDATE eshop.payment_info SET paid_externally=100 WHERE id=pid;
 PERFORM assert_eq(public.customer_order_payment_internal(child)->>'status','unknown'::text,'manual ambiguous payment');
 UPDATE eshop.payment_info SET paid_externally=NULL,paid=0 WHERE id=pid;
 UPDATE eshop.orders SET state='paid' WHERE id=child;
 PERFORM assert_eq(public.customer_order_payment_internal(child)->>'status','unknown'::text,'manual paid without bank fact');
 UPDATE eshop.orders SET state='storno' WHERE id=child;
 PERFORM assert_eq(public.customer_order_payment_internal(child)->>'instructionsAvailable','false'::text,'no payment request on cancellation');
 UPDATE eshop.orders SET state='preparing_payment' WHERE id=child;
 PERFORM assert_eq(public.customer_order_payment_internal(child)->>'status','preparing'::text,'preparing safe');
 UPDATE eshop.orders SET state='paid',price=0 WHERE id=child;
 PERFORM assert_eq(public.customer_order_payment_internal(child)->>'status','free'::text,'free not bank-paid');
 UPDATE eshop.orders SET state='ordered',price=100 WHERE id=child;
 -- Multiple products must still yield one admission.
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(child,ids[2],(x->>'product')::bigint);
 FOR raw IN SELECT unnest(ARRAY['ordered','paid','sent','used','paid','storno']) LOOP
  UPDATE eshop.tickets SET state=raw WHERE id=ids[2];
  r:=public.get_customer_order_overview(view_token,oid);
  PERFORM assert_eq(r#>>'{orders,1,tickets,0,rawState}',raw,'ticket refresh including unused reversal');
  PERFORM assert_eq(jsonb_array_length(r#>'{orders,1,tickets}'),1,'one distinct ticket');
 END LOOP;
 UPDATE forms SET is_open=false WHERE id=(x->>'form')::bigint;
 PERFORM assert_eq(public.get_customer_order_overview(view_token,oid)->>'code','200'::text,'closed form retains read');
 UPDATE eshop.waitlist_capabilities SET revoked_at=now() WHERE token_hash=delivery->>'tokenHash';
 PERFORM assert_eq(public.get_customer_order_overview(view_token,oid)->>'code','403'::text,'revoked view cannot read terminal');
 UPDATE eshop.waitlist_capabilities SET revoked_at=NULL,expires_at=now()-interval '1 second' WHERE token_hash=delivery->>'tokenHash';
 PERFORM assert_eq(public.get_customer_order_overview(view_token,oid)->>'code','403'::text,'expired view denied');
 PERFORM assert_true(NOT has_table_privilege('anon','eshop.order_overview_sources','SELECT'),'no public source read');
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.resolve_customer_order_access_v1(text,bigint,uuid,uuid,jsonb,uuid,boolean)','EXECUTE'),'no client issuance bypass');
 RAISE NOTICE 'PASS overview scope, partial/full, payment matrix, ticket refresh, expiry and revocation';
END $$;
ROLLBACK;
