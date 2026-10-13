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
CREATE FUNCTION pg_temp.checkout(x jsonb,persons uuid[] DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',
 CASE WHEN persons IS NULL THEN jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))
 ELSE (SELECT jsonb_agg(jsonb_build_object('participantId',id,'fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))) FROM unnest(persons) id) END);
$$;
CREATE FUNCTION pg_temp.delivery(code text,token text,oid bigint DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('orderId',oid,'recipient','regression@example.invalid','templateCode',code,
 'tokenHash',encode(extensions.digest(token,'sha256'),'hex'),'contentHash',repeat('f',64),'sealed',jsonb_build_object('ciphertext','sealed-test-double'));
$$;
CREATE FUNCTION pg_temp.register(x jsonb,n integer,token text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; payload jsonb;
BEGIN
 payload:=jsonb_build_object('form',x->'key','email','regression@example.invalid','people',(SELECT jsonb_agg(jsonb_build_object('fields','[]'::jsonb)) FROM generate_series(1,n)));
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
CREATE FUNCTION pg_temp.accept(x jsonb,w jsonb,persons uuid[],command uuid DEFAULT gen_random_uuid(),token text DEFAULT NULL,actor uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','personIds',to_jsonb(persons),'token',token,'orderDetails',pg_temp.checkout(x,persons)),command,'ac000000-0000-0000-0000-000000000001'::uuid,coalesce(actor,(x->>'actor')::uuid));
$$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(2); f bigint:=(x->>'form')::bigint; regular bigint; source bigint; child bigint; r jsonb; w jsonb; ids uuid[]; offered uuid[]; pick uuid; remaining uuid; token text:=repeat('b',64); cmd uuid:=gen_random_uuid(); seq bigint; symbol text; q timestamptz;
BEGIN
 FOR i IN 1..2 LOOP r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); PERFORM assert_eq(r->>'code','200'::text,'fill'); END LOOP;
 source:=(pg_temp.register(x,4)->>'order')::bigint;
 SELECT order_symbol,order_sequence INTO symbol,seq FROM eshop.orders WHERE id=source;
 FOR regular IN SELECT id FROM eshop.orders WHERE form=f AND state<>'waitlisted' LOOP PERFORM public.update_order_and_tickets_to_storno_221(regular); END LOOP;
 w:=pg_temp.offer(x,source,2,token);
 SELECT array_agg(participant_id ORDER BY id) INTO offered FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid;
 SELECT id INTO pick FROM eshop.order_participants WHERE current_order_id=source AND lifecycle='waiting' ORDER BY id LIMIT 1;
 r:=pg_temp.accept(x,w,ARRAY[pick],cmd); PERFORM assert_eq(r#>>'{data,code}','200'::text,'select another person');
 child:=(r#>>'{data,order,id}')::bigint;
 PERFORM assert_eq(r#>>'{data,conversion}','split'::text,'partial split');
 PERFORM assert_true(child<>source,'child identity');
 PERFORM assert_eq((SELECT source_waitlist_order_id FROM eshop.orders WHERE id=child),source,'child linked');
 PERFORM assert_true((SELECT current_order_id=child AND origin_order_id=source AND lifecycle='admitted' FROM eshop.order_participants WHERE id=pick),'stable selected person moved');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_participants WHERE current_order_id=source),3::bigint,'source shrinks');
 PERFORM assert_eq((SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND outcome='pending'),1::bigint,'other slot remains pending');
 r:=pg_temp.accept(x,w,ARRAY[pick],cmd); PERFORM assert_eq((r#>>'{data,order,id}')::bigint,child,'accept replay');
 SELECT participant_id INTO remaining FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND outcome='pending';
 SELECT queue_at INTO q FROM eshop.order_participants WHERE id=remaining;
 r:=public.execute_waitlist_command_client_sync_v1('decline',jsonb_build_object('offerId',w->'id','personIds',jsonb_build_array(remaining),'token',token),gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'decline selected slot');
 PERFORM assert_true((SELECT lifecycle='offer_declined' AND queue_at>q FROM eshop.order_participants WHERE id=remaining),'decline tail');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_participants WHERE current_order_id=source AND lifecycle='waiting'),2::bigint,'unoffered and swapped remainder waiting');
 w:=pg_temp.offer(x,source,1);
 SELECT participant_id INTO remaining FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND outcome='pending';
 UPDATE eshop.waitlist_offers SET created_at=now()-interval '2 hours',expires_at=clock_timestamp()-interval '1 second' WHERE id=(w->>'id')::uuid;
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal(f)->>'offeredPlaces')::integer,0,'expiry projection without cron');
 r:=pg_temp.accept(x,w,ARRAY[remaining]); PERFORM assert_true(r#>>'{data,code}' IS DISTINCT FROM '200','expired accept rejected');
 PERFORM public.expire_waitlist_form_internal(f);
 PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=remaining),'offer_expired'::text,'expiry lifecycle');
 w:=pg_temp.offer(x,source,1);
 SELECT participant_id INTO remaining FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND outcome='pending';
 r:=public.execute_waitlist_command_client_sync_v1('cancel',jsonb_build_object('offerId',w->'id','personIds',jsonb_build_array(remaining)),gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid);
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'editor cancel');
 PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=remaining),'offer_cancelled'::text,'distinct cancelled reason');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_participants WHERE current_order_id=source AND lifecycle='waiting'),0::bigint,'only offered people deactivated');
 r:=public.get_waitlist_offer_proposal(f);
 PERFORM assert_eq(jsonb_array_length(r->'recipients'),0,'automatic proposal skips declined expired cancelled');
 PERFORM assert_eq((SELECT order_symbol FROM eshop.orders WHERE id=source),symbol,'source symbol preserved');
 PERFORM assert_eq((SELECT order_sequence FROM eshop.orders WHERE id=source),seq,'source sequence preserved');
 RAISE NOTICE 'PASS split/person swap/replay/remaining/decline tail/expiry no cron';
END $$;
ROLLBACK;
