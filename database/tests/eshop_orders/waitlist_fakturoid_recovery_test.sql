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
DECLARE x jsonb; f bigint; source bigint; regular bigint; r jsonb; w jsonb; person uuid; remainder uuid; command uuid; target bigint; original_symbol text; original_sequence bigint; before_history bigint; price_id bigint; result_vs bigint;
BEGIN
 FOR people IN 1..2 LOOP
  x:=pg_temp.fixture(1); f:=(x->>'form')::bigint;
  r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); regular:=(r#>>'{order,id}')::bigint;
  source:=(pg_temp.register(x,people)->>'order')::bigint;
  SELECT order_symbol,order_sequence INTO original_symbol,original_sequence FROM eshop.orders WHERE id=source;
  PERFORM public.update_order_and_tickets_to_storno_221(regular);
  w:=pg_temp.offer(x,source,1);
  SELECT participant_id INTO person FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid;
  SELECT id INTO remainder FROM eshop.order_participants WHERE current_order_id=source AND id<>person;
  INSERT INTO eshop.external_services(unit,type,data) VALUES((x->>'unit')::bigint,'FAKTUROID','{}');
  command:=gen_random_uuid(); r:=pg_temp.accept(x,w,ARRAY[person],command);
  PERFORM assert_eq(r#>>'{data,code}','200'::text,'Fakturoid prepare'); target:=(r#>>'{data,order,id}')::bigint;
  PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=target),'preparing_payment'::text,'prepare state');
  PERFORM assert_eq((SELECT state FROM eshop.waitlist_acceptance_attempts WHERE command_id=command),'preparing'::text,'journal');
  PERFORM assert_jsonb_contains(public.get_form_capacity_snapshot_internal(f),'{"occupiedPeople":1,"offeredPlaces":0}','preparing counts once');
  BEGIN PERFORM public.check_order_is_mutable(target); RAISE EXCEPTION 'edit during prepare accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='edit during prepare accepted' THEN RAISE; END IF; END;
  BEGIN PERFORM public.update_order_and_tickets_to_storno_221(target); RAISE EXCEPTION 'cancel during prepare accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='cancel during prepare accepted' THEN RAISE; END IF; END;
  IF remainder IS NOT NULL THEN
   -- The unrelated remainder is still mutable while the accepted child prepares.
   r:=public.execute_waitlist_command_client_sync_v1('withdraw',jsonb_build_object('orderId',source,'personIds',jsonb_build_array(remainder)),gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid);
   PERFORM assert_eq(r#>>'{data,code}','200'::text,'unoffered remainder not blocked');
  END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM public.abort_fakturoid_ticket_order_v1(target,command);
  SELECT count(*) INTO before_history FROM eshop.orders_history WHERE "order"=source;
  PERFORM public.abort_fakturoid_ticket_order_v1(target,command);
  PERFORM assert_eq((SELECT count(*) FROM eshop.orders_history WHERE "order"=source),before_history,'abort replay no history duplication');
  PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=source),'waitlisted'::text,'source restored');
  PERFORM assert_eq((SELECT order_symbol FROM eshop.orders WHERE id=source),original_symbol,'abort symbol preserved');
  PERFORM assert_eq((SELECT order_sequence FROM eshop.orders WHERE id=source),original_sequence,'abort sequence preserved');
  PERFORM assert_true((SELECT current_order_id=source AND lifecycle='offered' AND ticket_id IS NULL FROM eshop.order_participants WHERE id=person),'person restored');
  PERFORM assert_eq((SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND outcome='pending'),1::bigint,'reservation restored');
  PERFORM assert_eq((SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=target),0::bigint,'failed products detached');
  PERFORM assert_eq((SELECT workflow_state FROM email_messages WHERE code='TICKET_ORDER_CONFIRMATION' AND data->>'command_id'=command::text),'cancelled'::text,'failed confirmation remains cancelled');
  IF remainder IS NOT NULL THEN
   PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=remainder),'withdrawn'::text,'abort preserves changed remainder');
   PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=target),'storno'::text,'failed child historical');
  END IF;
  BEGIN PERFORM public.complete_fakturoid_ticket_order_v1(target,command,123456789); RAISE EXCEPTION 'late complete accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%Acceptance attempt aborted%' THEN RAISE; END IF; END;
  -- Retry needs a new command; complete is idempotent and does not double capacity.
  command:=gen_random_uuid(); r:=pg_temp.accept(x,w,ARRAY[person],command);
  PERFORM assert_eq(r#>>'{data,code}','200'::text,'retry prepare'); target:=(r#>>'{data,order,id}')::bigint;
  PERFORM set_config('request.jwt.claim.sub','',true);
  result_vs:=public.complete_fakturoid_ticket_order_v1(target,command,123456789);
  PERFORM assert_eq(public.complete_fakturoid_ticket_order_v1(target,command,123456789),result_vs,'complete replay');
  PERFORM assert_eq((SELECT state FROM eshop.waitlist_acceptance_attempts WHERE command_id=command),'completed'::text,'journal completed');
  PERFORM assert_jsonb_contains(public.get_form_capacity_snapshot_internal(f),'{"occupiedPeople":1,"offeredPlaces":0}','complete capacity once');
 END LOOP;
 -- Expiry during provider preparation cannot restore a live capacity reservation.
 x:=pg_temp.fixture(1); f:=(x->>'form')::bigint;
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); regular:=(r#>>'{order,id}')::bigint;
 source:=(pg_temp.register(x,1)->>'order')::bigint;
 PERFORM public.update_order_and_tickets_to_storno_221(regular); w:=pg_temp.offer(x,source,1);
 SELECT participant_id INTO person FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid;
 INSERT INTO eshop.external_services(unit,type,data) VALUES((x->>'unit')::bigint,'FAKTUROID','{}');
 command:=gen_random_uuid(); r:=pg_temp.accept(x,w,ARRAY[person],command); target:=(r#>>'{data,order,id}')::bigint;
 PERFORM assert_eq(r#>>'{data,code}','200'::text,'expiry prepare');
 UPDATE eshop.waitlist_offers SET created_at=now()-interval '2 hours',expires_at=clock_timestamp()-interval '1 second' WHERE id=(w->>'id')::uuid;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM public.abort_fakturoid_ticket_order_v1(target,command);
 PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=person),'offer_expired'::text,'expired prepare abort person');
 PERFORM assert_eq((SELECT outcome FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid),'expired'::text,'expired prepare abort slot');
 PERFORM assert_jsonb_contains(public.get_form_capacity_snapshot_internal(f),'{"occupiedPeople":0,"offeredPlaces":0,"waitingPeople":0,"remainingPublic":1}','expiry abort releases capacity');
 RAISE NOTICE 'PASS Fakturoid full/split abort twice/complete twice/late complete/prepare locks/remainder/expiry';
END $$;
ROLLBACK;
