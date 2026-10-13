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
DECLARE x jsonb:=pg_temp.fixture(2); field_id bigint; choice_id bigint; choices_id bigint; p2 bigint; legacy jsonb; modern jsonb; r jsonb; a bigint; b bigint; source bigint; waiting bigint; w jsonb; before_count bigint; details jsonb;
BEGIN
 SELECT id INTO field_id FROM form_fields WHERE form=(x->>'form')::bigint AND product_type=(x->>'type')::bigint;
 INSERT INTO form_fields(form,type,is_ticket_field,title) VALUES((x->>'form')::bigint,'select_one',true,'Personal choice') RETURNING id INTO choice_id;
 INSERT INTO form_fields(form,type,is_ticket_field,title) VALUES((x->>'form')::bigint,'select_many',true,'Personal choices') RETURNING id INTO choices_id;
 UPDATE form_fields SET is_ticket_field=true,data='{"selection_type":"select_many"}' WHERE id=field_id;
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code) VALUES((x->>'type')::bigint,(x->>'occasion')::bigint,'Other selected default',150,'CZK') RETURNING id INTO p2;
 legacy:=jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(
  jsonb_build_object('product_type',x->'product','_subFieldId',field_id,'price',0.01),
  jsonb_build_object('product_type',p2,'_subFieldId',field_id,'price',0.01),
  jsonb_build_object('select_one','Blue','_subFieldId',choice_id,'price',0),
  jsonb_build_object('select_many',jsonb_build_array('Red','Green'),'_subFieldId',choices_id,'price',0)))));
 modern:=jsonb_set(legacy,'{ticket,0,fields}',jsonb_build_array(jsonb_build_object(field_id::text,x->'product'),jsonb_build_object(field_id::text,p2),jsonb_build_object(choice_id::text,'Blue','price',0),jsonb_build_object(choices_id::text,jsonb_build_array('Red','Green'),'price',0)));
 -- Both real transport shapes may repeat ONE multi-select field with distinct products.
 r:=public.create_ticket_order_internal_v1(legacy); PERFORM assert_eq(r->>'code','200'::text,'legacy distinct multi-select product defaults accepted'); a:=(r#>>'{order,id}')::bigint;
 r:=public.create_ticket_order_internal_v1(modern); PERFORM assert_eq(r->>'code','200'::text,'modern distinct multi-select product defaults accepted'); b:=(r#>>'{order,id}')::bigint;
 FOREACH source IN ARRAY ARRAY[a,b] LOOP
  PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=source),250::numeric,'both selected products use server prices totaling250');
  PERFORM assert_eq(cardinality(pg_temp.ticket_ids(source)),1,'two selected products create one ticket identity');
  PERFORM assert_eq((SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=source AND product IS NOT NULL),2::bigint,'both selections have product rows');
  PERFORM assert_eq((SELECT data FROM eshop.tickets WHERE id=(pg_temp.ticket_ids(source))[1]),jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(choice_id::text,'Blue'),jsonb_build_object(choices_id::text,jsonb_build_array('Red','Green')))),'personal choices retain stable values without UI price or typed metadata');
 END LOOP;
 source:=(pg_temp.register(x,1)->>'order')::bigint; waiting:=(pg_temp.ticket_ids(source))[1];
 PERFORM public.update_order_and_tickets_to_storno_221(a); PERFORM public.update_order_and_tickets_to_storno_221(b);
 w:=pg_temp.offer(x,source,1);
 details:=jsonb_set(legacy,'{ticket,0,ticketId}',to_jsonb(waiting),true);
 r:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','ticketIds',jsonb_build_array(waiting),'orderDetails',details),gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid);
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'offer accepts distinct multi-select products');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=source),250::numeric,'offer server price sums250');
 PERFORM assert_eq((SELECT data FROM eshop.tickets WHERE id=waiting),jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(choice_id::text,'Blue'),jsonb_build_object(choices_id::text,jsonb_build_array('Red','Green')))),'offered personal choice prices are ignored and values retained');
 PERFORM assert_eq(pg_temp.ticket_ids(source),ARRAY[waiting],'offer reuses the same BIGINT ticket');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=source AND product IS NOT NULL),2::bigint,'offered ticket owns both products');
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal((x->>'form')::bigint)->>'occupiedPeople')::integer,1,'two products occupy one place');
 PERFORM public.update_order_and_tickets_to_storno_221(source);
 SELECT count(*) INTO before_count FROM eshop.orders WHERE form=(x->>'form')::bigint;
 r:=public.create_ticket_order_internal_v1(jsonb_set(legacy,'{ticket,0,fields,1}',legacy#>'{ticket,0,fields,0}'));
 PERFORM assert_eq(r->>'message','FORM_FIELD_AMBIGUOUS'::text,'same product cannot be selected twice');
 UPDATE form_fields SET data='{"selection_type":"select_one"}' WHERE id=field_id;
 r:=public.create_ticket_order_internal_v1(legacy); PERFORM assert_eq(r->>'message','FORM_FIELD_AMBIGUOUS'::text,'single-select repeated field still rejected');
 UPDATE form_fields SET data='{}' WHERE id=field_id;
 r:=public.create_ticket_order_internal_v1(modern); PERFORM assert_eq(r->>'message','FORM_FIELD_AMBIGUOUS'::text,'omitted selection mode remains single-select');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE form=(x->>'form')::bigint),before_count,'invalid repeat rolls back all orders/tickets/products');
END $$;
ROLLBACK;
