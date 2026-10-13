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
DECLARE x jsonb:=pg_temp.fixture(1); r jsonb; source bigint; regular bigint; ordinary bigint; waiting bigint; hidden bigint; scan text:='scan-'||gen_random_uuid()::text; msg public.email_messages; lease uuid:=gen_random_uuid(); attempt uuid; w jsonb;
BEGIN
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); PERFORM assert_eq(r->>'code','200'::text,'ordinary create'); regular:=(r#>>'{order,id}')::bigint;
 ordinary:=(pg_temp.ticket_ids(regular))[1];
 source:=(pg_temp.register(x,1)->>'order')::bigint; waiting:=(pg_temp.ticket_ids(source))[1];
 INSERT INTO occasions_hidden(secret) VALUES(scan) RETURNING id INTO hidden;
 UPDATE occasions SET occasion_hidden=hidden WHERE id=(x->>'occasion')::bigint;
 r:=public.get_all_tickets_for_scan(scan);
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(r) ticket WHERE ticket->>'id'=ordinary::text),'ordinary ticket remains in scanner download');
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(r) ticket WHERE ticket->>'id'=waiting::text),'waiting ticket excluded from scanner download');
 PERFORM assert_not_null(public.get_ticket_details_for_generating(ordinary)#>>'{ticket,id}','ordinary PDF details available');
 PERFORM assert_true(public.get_ticket_details_for_generating(waiting) IS NULL OR public.get_ticket_details_for_generating(waiting)#>>'{ticket,id}' IS NULL,'waiting PDF details unavailable');
 PERFORM assert_true(public.get_tickets_with_details(source) IS NULL OR jsonb_array_length(public.get_tickets_with_details(source))=0,'waiting order emits no ticket delivery list');
 r:=public.update_ticket_to_used(waiting,scan); PERFORM assert_true(r->>'code' IS DISTINCT FROM '200','scan-code mutation rejects waiting ticket');
 BEGIN PERFORM public.update_ticket_to_used_ws(waiting); RAISE EXCEPTION 'waiting ws use accepted'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 PERFORM assert_true((SELECT state='waitlisted' AND ticket_symbol IS NULL FROM eshop.tickets WHERE id=waiting),'all admission attempts leave waiting ticket invalid');
 r:=public.update_ticket_to_used(ordinary,scan); PERFORM assert_eq(r->>'code','200'::text,'same scan-code operation works on regular ticket');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ordinary),'used'::text,'ordinary ticket is used');
 PERFORM public.enqueue_paid_order_tickets(source);
 PERFORM assert_eq((SELECT count(*) FROM email_messages WHERE order_id=source AND message_kind='order_tickets'),0::bigint,'waiting never enters automatic paid ticket producer');
 -- Even a malformed internal delivery intent is fenced by the canonical queue.
 PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',source),(x->>'organization')::bigint,(x->>'occasion')::bigint,(x->>'unit')::bigint);
 SELECT * INTO msg FROM email_messages WHERE order_id=source AND message_kind='order_tickets';
 PERFORM assert_false(public.email_intent_valid(msg),'waiting ticket delivery intent invalid');
 UPDATE email_messages SET workflow_state='preparing',lease_token=lease,lease_until=now()+interval '90 seconds' WHERE id=msg.id;
 INSERT INTO email_attempts(message_id,lease_token,state) VALUES(msg.message_id,lease,'preparing') RETURNING attempt_id INTO attempt;
 PERFORM public.prepare_email(msg.message_id,lease,'{"ciphertext":"sealed-test-double"}');
 r:=public.begin_email_send(attempt,lease); PERFORM assert_eq(r->>'disposition','cancelled'::text,'waiting delivery cancelled before provider permit');
 PERFORM assert_true((SELECT began_at IS NULL FROM email_attempts WHERE attempt_id=attempt),'waiting delivery has no provider-start permit');
 PERFORM public.update_order_and_tickets_to_storno_221(regular); w:=pg_temp.offer(x,source,1);
 PERFORM public.internal_storno_tickets_221(ARRAY[waiting]);
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=waiting),'storno'::text,'canonical ticket cancellation is waiting withdrawal truth');
 PERFORM assert_eq(public.get_effective_waitlist_ticket_lifecycle_internal(waiting),'withdrawn'::text,'withdrawal derived from existing invalid ticket');
 PERFORM assert_eq((SELECT outcome FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid),'cancelled'::text,'generic ticket cancellation releases pending offer');
 PERFORM assert_jsonb_contains(public.get_form_capacity_snapshot_internal((x->>'form')::bigint),'{"occupiedPeople":0,"offeredPlaces":0,"waitingPeople":0,"remainingPublic":1}','one cancellation path releases all occupancy');
END $$;
ROLLBACK;
