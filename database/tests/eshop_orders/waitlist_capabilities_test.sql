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
DECLARE x jsonb:=pg_temp.fixture(1); y jsonb:=pg_temp.fixture(1); r jsonb; source bigint; other bigint; regular bigint; w jsonb; person uuid; token text:=repeat('c',64); manage text:=repeat('d',64); cmd uuid:=gen_random_uuid(); client uuid:=gen_random_uuid(); payload jsonb; original jsonb; before_count bigint; viewer uuid;
BEGIN
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); regular:=(r#>>'{order,id}')::bigint;
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(y));
 source:=(pg_temp.register(x,2,manage)->>'order')::bigint; other:=(pg_temp.register(y,1)->>'order')::bigint;
 PERFORM public.update_order_and_tickets_to_storno_221(regular);
 w:=pg_temp.offer(x,source,1,token);
 SELECT participant_id INTO person FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN PERFORM public.execute_waitlist_command_client_sync_v1('withdraw',jsonb_build_object('orderId',source),gen_random_uuid(),client); RAISE EXCEPTION 'nonservice command accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 SELECT count(*) INTO before_count FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND outcome='pending';
 r:=public.get_waitlist_offer_form(token,(w->>'id')::uuid,NULL); PERFORM assert_eq(r->>'code','200'::text,'valid read');
 r:=public.get_waitlist_offer_form(token,(w->>'id')::uuid,NULL); PERFORM assert_eq(r->>'code','200'::text,'repeat GET');
 PERFORM assert_eq((SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND outcome='pending'),before_count,'GET has no mutation');
 r:=public.get_waitlist_offer_form(repeat('e',64),(w->>'id')::uuid,NULL); PERFORM assert_eq(r->>'code','403'::text,'wrong token fails');
 r:=public.get_waitlist_offer_form(manage,NULL,other); PERFORM assert_eq(r->>'code','403'::text,'cross tenant manage fails');
 SELECT id INTO viewer FROM eshop.order_participants WHERE current_order_id=other;
 r:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','personIds',jsonb_build_array(viewer),'token',token,'orderDetails',pg_temp.checkout(x,ARRAY[viewer])),gen_random_uuid(),client);
 PERFORM assert_true(r#>>'{data,code}' IS DISTINCT FROM '200','cross tenant person tampering rejected');
 r:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','personIds',jsonb_build_array(person,person),'token',token,'orderDetails',pg_temp.checkout(x,ARRAY[person,person])),gen_random_uuid(),client);
 PERFORM assert_true(r#>>'{data,code}' IS DISTINCT FROM '200','duplicate persons rejected');
 payload:=jsonb_build_object('offerId',w->'id','personIds',jsonb_build_array(person),'token',token,'orderDetails',pg_temp.checkout(x,ARRAY[person]));
 original:=public.execute_waitlist_command_client_sync_v1('accept',payload,cmd,client);
 PERFORM assert_eq(original#>>'{data,code}','200'::text,'capability acceptance');
 r:=public.execute_waitlist_command_client_sync_v1('accept',payload,cmd,client); PERFORM assert_eq(r,original,'replay returns original');
 r:=public.execute_waitlist_command_client_sync_v1('accept',payload||'{"extra":true}',cmd,client); PERFORM assert_eq(r->>'errorCode','COMMAND_PAYLOAD_CONFLICT'::text,'changed payload conflicts');
 PERFORM assert_eq((SELECT count(*) FROM email_messages WHERE code='TICKET_ORDER_CONFIRMATION' AND data->>'command_id'=cmd::text),1::bigint,'confirmation exactly once');
 r:=public.get_waitlist_offer_form(token,(w->>'id')::uuid,NULL);
 PERFORM assert_eq(r->>'offerStatus','accepted'::text,'revoked accepted link minimal status');
 PERFORM assert_true(r->'form'='null'::jsonb AND r->'participants'='[]'::jsonb AND NOT r ? 'orderData','terminal accepted link hides private data');
 UPDATE eshop.waitlist_offers SET created_at=now()-interval '2 hours',expires_at=clock_timestamp()-interval '1 second' WHERE id=(w->>'id')::uuid;
 r:=public.get_waitlist_offer_form(token,(w->>'id')::uuid,NULL);
 PERFORM assert_eq(r->>'offerStatus','expired'::text,'expired revoked link minimal status');
 PERFORM assert_true(r->'form'='null'::jsonb AND r->'participants'='[]'::jsonb AND NOT r ? 'orderData','terminal expired link hides private data');
 r:=public.execute_waitlist_command_client_sync_v1('accept',payload,gen_random_uuid(),client);
 PERFORM assert_true(r#>>'{data,code}' IS DISTINCT FROM '200','terminal capability cannot write');
 payload:=jsonb_build_object('orderId',source,'personIds',jsonb_build_array(person),'token',manage);
 r:=public.execute_waitlist_command_client_sync_v1('withdraw',payload,gen_random_uuid(),client);
 PERFORM assert_true(r#>>'{data,code}' IS DISTINCT FROM '200','cannot withdraw accepted person');
 SELECT id INTO person FROM eshop.order_participants WHERE current_order_id=source AND lifecycle='waiting';
 r:=public.execute_waitlist_command_client_sync_v1('withdraw',jsonb_build_object('orderId',source,'personIds',jsonb_build_array(person),'token',manage),gen_random_uuid(),client);
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'withdraw selected remaining person');
 PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=person),'withdrawn'::text,'only selected withdrawn');
 -- Viewer role can read admin detail but cannot act as an order editor.
 PERFORM create_user_for_test('waitlist_viewer','viewer-'||gen_random_uuid()::text||'@example.invalid');
 viewer:=get_user_id('waitlist_viewer');
 IF viewer IS NULL THEN RAISE EXCEPTION 'Second bootstrap user required'; END IF;
 INSERT INTO occasion_users(occasion,"user",is_editor_order_view,is_editor_order) VALUES((x->>'occasion')::bigint,viewer,true,false);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 r:=public.get_waitlist_order_detail(source); PERFORM assert_eq((r->>'orderId')::bigint,source,'viewer read');
 BEGIN PERFORM public.execute_waitlist_command_client_sync_v1('send',jsonb_build_object('formId',x->'form'),gen_random_uuid(),client,viewer); RAISE EXCEPTION 'viewer send accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RAISE NOTICE 'PASS capabilities/GET safety/cross tenant/replay/hash conflict/email dedupe/selected withdrawal/viewer';
END $$;
ROLLBACK;
