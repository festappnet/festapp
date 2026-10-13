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
DECLARE x jsonb:=pg_temp.fixture(NULL); f bigint:=(x->>'form')::bigint; n text; r jsonb; o bigint; bad boolean; bp bigint; copied bigint; second bigint;
BEGIN
 PERFORM assert_true((SELECT participant_capacity IS NULL AND NOT waitlist_enabled AND show_remaining_capacity FROM forms WHERE id=f),'unlimited defaults');
 PERFORM assert_eq(public.get_form_registration_mode_internal(f),'regular'::text,'unlimited regular mode');
 FOREACH n IN ARRAY ARRAY['order_participants','waitlist_offers','waitlist_offer_slots','waitlist_capabilities','waitlist_acceptance_attempts','form_participant_backfill_issues'] LOOP
  PERFORM assert_true((SELECT relrowsecurity FROM pg_class WHERE oid=('eshop.'||n)::regclass),'RLS enabled '||n);
  PERFORM assert_false(has_table_privilege('anon','eshop.'||n,'SELECT'),'anon table read '||n);
  PERFORM assert_false(has_table_privilege('authenticated','eshop.'||n,'INSERT,UPDATE,DELETE'),'authenticated writes '||n);
 END LOOP;
 PERFORM assert_false(has_function_privilege('anon','public.accept_waitlist_offer_internal(jsonb,uuid,uuid)','EXECUTE'),'private accept ACL');
 PERFORM assert_false(has_function_privilege('authenticated','public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb)','EXECUTE'),'only service commands');
 BEGIN UPDATE forms SET participant_capacity=0 WHERE id=f; RAISE EXCEPTION 'zero capacity accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN UPDATE forms SET waitlist_enabled=true,waitlist_offer_duration_seconds=1 WHERE id=f; RAISE EXCEPTION 'unlimited waitlist accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO eshop.blueprints(organization,occasion,title) VALUES((x->>'organization')::bigint,(x->>'occasion')::bigint,'Blueprint') RETURNING id INTO bp;
 UPDATE forms SET blueprint=bp WHERE id=f;
 PERFORM assert_eq(public.get_form_registration_mode_internal(f),'blueprint'::text,'blueprint mode');
 BEGIN UPDATE forms SET participant_capacity=1 WHERE id=f; RAISE EXCEPTION 'blueprint capacity accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 UPDATE forms SET blueprint=NULL,participant_capacity=3,waitlist_enabled=true,waitlist_offer_duration_seconds=3600 WHERE id=f;
 BEGIN UPDATE forms SET waitlist_offer_duration_seconds=NULL WHERE id=f; RAISE EXCEPTION 'NULL offer duration accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN UPDATE forms SET waitlist_offer_duration_seconds=0 WHERE id=f; RAISE EXCEPTION 'zero offer duration accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 r:=public.update_form_internal_v1(jsonb_build_object('id',f,'occasion',x->'occasion','link',x->'link','show_remaining_capacity',false));
 PERFORM assert_eq(r->>'code','200'::text,'partial settings save');
 PERFORM assert_true((SELECT participant_capacity=3 AND waitlist_enabled AND NOT show_remaining_capacity FROM forms WHERE id=f),'omitted settings preserved');
 UPDATE occasion_users SET is_editor_view=true WHERE occasion=(x->>'occasion')::bigint AND "user"=(x->>'actor')::uuid;
 copied:=public.duplicate_form_to_occasion(f,x->>'link');
 PERFORM assert_true((SELECT participant_capacity=3 AND waitlist_enabled AND NOT show_remaining_capacity FROM forms WHERE id=copied),'copy preserves settings');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE form=copied),0::bigint,'copy does not copy live orders');
 r:=public.update_form_internal_v1(jsonb_build_object('id',f,'occasion',x->'occasion','link',x->'link','participant_capacity',NULL,'waitlist_enabled',false));
 PERFORM assert_eq(r->>'code','200'::text,'explicit NULL removes inactive limit');
 PERFORM assert_true((SELECT participant_capacity IS NULL FROM forms WHERE id=f),'NULL stored');
 o:=public.allocate_ticket_order_identity_internal(f);
 INSERT INTO forms(occasion,link) VALUES((x->>'occasion')::bigint,gen_random_uuid()::text) RETURNING id INTO second;
 BEGIN INSERT INTO eshop.order_participants(current_order_id,origin_order_id,form_id,lifecycle) VALUES(o,o,second,'waiting'); RAISE EXCEPTION 'cross-form ledger accepted'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN UPDATE eshop.orders SET state='waitlisted',price=0 WHERE id=o; RAISE EXCEPTION 'waitlist zero finance accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO eshop.form_participant_backfill_issues(order_id,form_id,reason) VALUES(o,f,'ambiguous regression person');
 BEGIN PERFORM public.check_form_capacity_settings_internal(f,'{"participant_capacity":3}'); RAISE EXCEPTION 'ambiguous activation accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%PARTICIPANT_BACKFILL_REQUIRED%' THEN RAISE; END IF; END;
 RAISE NOTICE 'PASS schema/defaults/CHECK/ACL/RLS/partial settings/ambiguity';
END $$;
ROLLBACK;
