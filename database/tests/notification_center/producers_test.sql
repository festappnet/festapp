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
DECLARE x jsonb:=pg_temp.fixture(10); org bigint:=(x->>'organization')::bigint; f bigint:=(x->>'form')::bigint;
 r jsonb; oid bigint; ev uuid; id1 bigint; w jsonb; ids bigint[]; cmd uuid:=gen_random_uuid(); n bigint;
BEGIN
 PERFORM public.initialize_notification_center_internal(org);
 -- Anonymous customer, not the synthetic admin author.
 PERFORM set_config('request.jwt.claim.sub','',true);
 FOR i IN 1..10 LOOP
  r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x));
  PERFORM assert_eq(r->>'code','200'::text,'real checkout succeeds: '||r::text);
  oid:=(r#>>'{order,id}')::bigint;
  IF i=1 THEN id1:=oid; END IF;
 END LOOP;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='order_created'),10::bigint,'one event per real checkout');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='capacity_full'),1::bigint,'90 then full is one episode');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND kind='capacity_full' AND status='active'),'capacity episode active');
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x));
 PERFORM assert_true(r->>'code'<>'200','overcapacity rejected');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='order_created'),10::bigint,'failed checkout no event');
 PERFORM public.cancel_order_domain_internal_v1(id1,false);
 PERFORM public.cancel_order_domain_internal_v1(id1,false);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='order_cancelled'),1::bigint,'repeated whole cancellation exactly once');
 PERFORM public.project_notification_center(100);
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 PERFORM assert_true((public.get_notification_center_badge(org)->>'unread')::boolean,'real customer order reaches editor');
 PERFORM public.open_notification_center(org);
 -- Payment changes state only, no added delivery.
 SELECT last_delivery_sequence INTO n FROM public.notification_center_user_state WHERE organization=org AND recipient=(x->>'actor')::uuid;
 PERFORM public.notification_center_order_state_internal(oid);PERFORM public.project_notification_center(100);
 PERFORM assert_eq((SELECT last_delivery_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=(x->>'actor')::uuid),n,'state refresh has no attention');
 -- A pre-generated stock shell is not a customer cancellation notification.
 UPDATE eshop.orders SET state='stock',price=NULL,payment_info=NULL WHERE id=id1;
 PERFORM public.notification_center_order_internal(id1,'order_cancelled','stock-void');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='order_cancelled'),1::bigint,'stock inventory does not emit a customer-order cancellation');
 -- Repeated initialization preserves the original collection boundary and events.
 PERFORM public.initialize_notification_center_internal(org);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='order_created'),10::bigint,'initialization does not replay');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(2); org bigint:=(x->>'organization')::bigint; f bigint:=(x->>'form')::bigint;
 r jsonb; source bigint; regular bigint; w jsonb; ids bigint[]; command uuid:=gen_random_uuid();
BEGIN
 PERFORM public.initialize_notification_center_internal(org);
 FOR i IN 1..2 LOOP r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x));PERFORM assert_eq(r->>'code','200'::text,'waitlist setup checkout');END LOOP;
 source:=(pg_temp.register(x,3)->>'order')::bigint;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='waitlist_registered'),1::bigint,'waitlist registration emits once');
 FOR regular IN SELECT id FROM eshop.orders WHERE form=f AND state<>'waitlisted' LOOP PERFORM public.cancel_order_domain_internal_v1(regular,false);END LOOP;
 w:=pg_temp.offer(x,source,2,repeat('c',64));
 ids:=pg_temp.ticket_ids(source);
 r:=pg_temp.accept(x,w,ARRAY[ids[1]],command);
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'partial acceptance works');
 r:=pg_temp.accept(x,w,ARRAY[ids[1]],command);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='offer_accepted'),1::bigint,'partial acceptance replay emits once');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='order_created'),2::bigint,'acceptance is not another new order alert');
 PERFORM public.expire_waitlist_form_internal(f,clock_timestamp()+interval '2 hours');
 PERFORM public.expire_waitlist_form_internal(f,clock_timestamp()+interval '2 hours');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='offer_expired'),1::bigint,'maintenance expiration emits once');
 PERFORM assert_eq((SELECT (data->>'count')::integer FROM public.notification_center_events WHERE organization=org AND kind='offer_expired'),1,'only remaining pending slot expires');
END $$;
ROLLBACK;
