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
DECLARE x jsonb:=pg_temp.fixture(5); f bigint:=(x->>'form')::bigint; regular bigint; source bigint; r jsonb; c jsonb; w jsonb; persons bigint[]; before_symbol text; before_sequence bigint;
BEGIN
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x));
 PERFORM assert_eq(r->>'code','200'::text,'regular checkout'); regular:=(r#>>'{order,id}')::bigint;
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal(f)->>'occupiedPeople')::integer,1,'one person per ticket');
 -- Force full occupancy through ordinary checkouts, never fake admitted counts.
 FOR i IN 2..5 LOOP r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); PERFORM assert_eq(r->>'code','200'::text,'fill capacity'); END LOOP;
 r:=pg_temp.register(x,2); source:=(r->>'order')::bigint;
 SELECT order_symbol,order_sequence INTO before_symbol,before_sequence FROM eshop.orders WHERE id=source;
 UPDATE eshop.orders SET created_at=now()-interval '7 days' WHERE id=source;
 UPDATE forms SET deadline_duration_seconds=86400 WHERE id=f;
 PERFORM assert_true((SELECT price IS NULL AND payment_info IS NULL AND state='waitlisted' FROM eshop.orders WHERE id=source),'waitlist has no finance');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=source AND product IS NOT NULL),0::bigint,'waitlist has no products or tickets');
 FOR regular IN SELECT id FROM eshop.orders WHERE form=f AND state<>'waitlisted' LOOP PERFORM public.update_order_and_tickets_to_storno_221(regular); END LOOP;
 c:=public.get_form_capacity_snapshot_internal(f);
 PERFORM assert_jsonb_contains(c,'{"occupiedPeople":0,"waitingPeople":2,"offeredPlaces":0,"remainingPublic":3,"offerablePlaces":5,"heldForWaiting":2}','release five waiting two gives P three');
 PERFORM assert_eq((SELECT count(*) FROM eshop.waitlist_offers WHERE form_id=f),0::bigint,'release does not automatically send');
 PERFORM public.check_form_capacity_settings_internal(f,'{"participant_capacity":1}');
 BEGIN PERFORM public.check_form_capacity_settings_internal(f,'{"participant_capacity":null}'); RAISE EXCEPTION 'remove active limit allowed'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%WAITLIST_HAS_ACTIVE_ENTRIES%' THEN RAISE; END IF; END;
 BEGIN PERFORM public.check_form_capacity_settings_internal(f,'{"blueprint":1}'); RAISE EXCEPTION 'blueprint active allowed'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%WAITLIST_HAS_ACTIVE_ENTRIES%' THEN RAISE; END IF; END;
 BEGIN PERFORM public.check_form_capacity_settings_internal(f,'{"waitlist_enabled":false}'); RAISE EXCEPTION 'disable active allowed'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%WAITLIST_HAS_ACTIVE_ENTRIES%' THEN RAISE; END IF; END;
 w:=pg_temp.offer(x,source,2);
 BEGIN PERFORM public.check_form_capacity_settings_internal(f,'{"participant_capacity":1}'); RAISE EXCEPTION 'below reserved allowed'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%CAPACITY_BELOW_COMMITTED%' THEN RAISE; END IF; END;
 SELECT array_agg(id ORDER BY id) INTO persons FROM pg_temp.ticket_rows WHERE current_order_id=source;
 UPDATE eshop.products SET maximum=1 WHERE id=(x->>'product')::bigint;
 r:=pg_temp.accept(x,w,persons);
 PERFORM assert_true(r#>>'{data,code}' IS DISTINCT FROM '200','sold-out product fails');
 PERFORM assert_eq(r#>>'{data,errorCode}','PRODUCT_CAPACITY_EXCEEDED'::text,'product failure is specific');
 PERFORM assert_eq((SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND outcome='pending'),2::bigint,'failure keeps all pending');
 PERFORM assert_true((SELECT state='waitlisted' AND price IS NULL AND payment_info IS NULL FROM eshop.orders WHERE id=source),'product failure rolls back finance');
 UPDATE eshop.products SET maximum=NULL WHERE id=(x->>'product')::bigint;
 UPDATE forms SET is_open=false WHERE id=f;
 PERFORM assert_eq(public.get_form_registration_mode_internal(f),'closed'::text,'public registration closed');
 r:=pg_temp.accept(x,w,persons);
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'valid offer accepts closed form');
 PERFORM assert_eq((r#>>'{data,order,id}')::bigint,source,'full preserves identity');
 PERFORM assert_eq(r#>>'{data,conversion}','in_place'::text,'full conversion');
 PERFORM assert_eq((SELECT order_symbol FROM eshop.orders WHERE id=source),before_symbol,'full symbol preserved');
 PERFORM assert_eq((SELECT order_sequence FROM eshop.orders WHERE id=source),before_sequence,'full sequence preserved');
 PERFORM assert_true((SELECT pi.deadline BETWEEN now()+interval '1 day' AND clock_timestamp()+interval '1 day' FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=source),'normal payment deadline starts at acceptance');
 PERFORM assert_jsonb_contains(public.get_form_capacity_snapshot_internal(f),'{"occupiedPeople":2,"offeredPlaces":0,"waitingPeople":0,"remainingPublic":3}','accept moves R to O');
 RAISE NOTICE 'PASS capacity/hold/settings/product rollback/closed offer/full identity';
END $$;
ROLLBACK;
