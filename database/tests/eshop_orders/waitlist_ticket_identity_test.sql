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
DECLARE x jsonb:=pg_temp.fixture(2); f bigint:=(x->>'form')::bigint; r jsonb; source bigint; regular bigint; field_id bigint; ids bigint[]; ticket_a bigint; ticket_b bigint; p2 bigint; w jsonb; details jsonb; before_count bigint;
BEGIN
 FOR i IN 1..2 LOOP r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); PERFORM assert_eq(r->>'code','200'::text,'fill regular capacity'); END LOOP;
 INSERT INTO form_fields(form,type,is_ticket_field,is_required,title) VALUES(f,'text',true,true,'Per-ticket number') RETURNING id INTO field_id;
 r:=public.execute_waitlist_command_client_sync_v1('register',jsonb_build_object('form',x->'key','email','regression@example.invalid','tickets',jsonb_build_array(
  jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(field_id::text,100))),
  jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(field_id::text,200))))),gen_random_uuid(),gen_random_uuid(),NULL,
  jsonb_build_array(pg_temp.delivery('waitlist_confirmation',repeat('7',64))));
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'register numeric ticket answers'); source:=(r#>>'{data,order,id}')::bigint;
 ids:=pg_temp.ticket_ids(source); PERFORM assert_eq(cardinality(ids),2,'exactly two existing waiting ticket identities');
 SELECT id INTO ticket_a FROM eshop.tickets WHERE id=ANY(ids) AND data#>>ARRAY['fields','0',field_id::text]='100';
 SELECT id INTO ticket_b FROM eshop.tickets WHERE id=ANY(ids) AND data#>>ARRAY['fields','0',field_id::text]='200';
 PERFORM assert_not_null(ticket_a,'100 bound to one ticket'); PERFORM assert_not_null(ticket_b,'200 bound to another ticket');
 PERFORM assert_true(ticket_a<>ticket_b,'answers have separate stable ticket owners');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE id=ANY(ids) AND state='waitlisted' AND ticket_symbol IS NULL),2::bigint,'waiting tickets are non-valid and have no QR symbol');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=source AND product IS NULL),2::bigint,'existing null-product OPT anchors waiting tickets');
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal(f)->>'occupiedPeople')::integer,2,'waiting tickets excluded from regular occupancy');
 FOR regular IN SELECT id FROM eshop.orders WHERE form=f AND state<>'waitlisted' LOOP PERFORM public.update_order_and_tickets_to_storno_221(regular); END LOOP;
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal(f)->>'occupiedPeople')::integer,0,'ordinary cancellation directly frees occupied tickets');
 w:=pg_temp.offer(x,source,2);
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code) VALUES((x->>'type')::bigint,(x->>'occasion')::bigint,'Second ticket product',200,'CZK') RETURNING id INTO p2;
 -- Reverse submitted ticket order to expose accidental positional answer/product binding.
 details:=jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',jsonb_build_array(
  jsonb_build_object('ticketId',ticket_b,'fields',jsonb_build_array(jsonb_build_object(field_id::text,200),jsonb_build_object('product_type',p2))),
  jsonb_build_object('ticketId',ticket_a,'fields',jsonb_build_array(jsonb_build_object(field_id::text,100),jsonb_build_object('product_type',x->'product')))));
 SELECT count(*) INTO before_count FROM eshop.tickets WHERE occasion=(x->>'occasion')::bigint;
 r:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','ticketIds',jsonb_build_array(ticket_b,ticket_a),'orderDetails',details),gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid);
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'full numeric ticket acceptance');
 PERFORM assert_eq((r#>>'{data,order,id}')::bigint,source,'full order identity preserved');
 PERFORM assert_eq(pg_temp.ticket_ids(source),ids,'full acceptance reuses the SAME actual ticket IDs');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=(x->>'occasion')::bigint),before_count,'acceptance creates no replacement person tickets');
 PERFORM assert_eq((SELECT data#>>ARRAY['fields','0',field_id::text] FROM eshop.tickets WHERE id=ticket_a),'100'::text,'first answer remains 100');
 PERFORM assert_eq((SELECT data#>>ARRAY['fields','0',field_id::text] FROM eshop.tickets WHERE id=ticket_b),'200'::text,'second answer remains 200');
 PERFORM assert_eq((SELECT product FROM eshop.order_product_ticket WHERE "order"=source AND ticket=ticket_a AND product IS NOT NULL),(x->>'product')::bigint,'100 owns first selected product');
 PERFORM assert_eq((SELECT product FROM eshop.order_product_ticket WHERE "order"=source AND ticket=ticket_b AND product IS NOT NULL),p2,'200 owns different selected product');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE id=ANY(ids) AND state='ordered' AND ticket_symbol IS NOT NULL),2::bigint,'only admission creates valid ordinary ticket symbols');
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal(f)->>'occupiedPeople')::integer,2,'actual ticket counts replace offer reservations');
END $$;
ROLLBACK;
