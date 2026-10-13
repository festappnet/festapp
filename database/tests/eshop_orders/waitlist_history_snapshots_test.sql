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
-- Immutable history preserves the registration group and pre-accept answers,
-- independently of subsequent participant movement or editing.
DO $$
DECLARE x jsonb; source bigint; regular bigint; target bigint; person uuid; field_id bigint; w jsonb; result jsonb;
 payload jsonb; details jsonb; registration jsonb; acceptance jsonb; mode text; source_history bigint; target_history bigint;
 original_ids jsonb; registration_cmd uuid; accept_cmd uuid;
BEGIN
 FOREACH mode IN ARRAY ARRAY['split','in_place'] LOOP
  x:=pg_temp.fixture(2);
  FOR i IN 1..2 LOOP
   result:=public.create_ticket_order_internal_v1(pg_temp.checkout(x));
   IF result->>'code'<>'200' THEN RAISE EXCEPTION 'Fill failed %',result; END IF;
  END LOOP;
  INSERT INTO form_fields(form,type,is_ticket_field,is_required,title)
   VALUES((x->>'form')::bigint,'text',true,false,'Historic answer') RETURNING id INTO field_id;
  payload:=jsonb_build_object('form',x->'key','email','regression@example.invalid','people',jsonb_build_array(
   jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(field_id::text,'Original A')),'secret','never-history'),
   jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(field_id::text,'Original B')),'token','never-history')));
  registration_cmd:=gen_random_uuid();
  result:=public.execute_waitlist_command_client_sync_v1('register',payload,registration_cmd,gen_random_uuid(),NULL,
   jsonb_build_array(pg_temp.delivery('waitlist_confirmation',encode(extensions.gen_random_bytes(32),'hex'))));
  IF result#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Registration failed %',result; END IF;
  source:=(result#>>'{data,order,id}')::bigint;
  SELECT id,data INTO source_history,registration FROM eshop.orders_history
   WHERE "order"=source AND data->>'action'='waitlist_register';
  PERFORM assert_eq(jsonb_array_length(registration->'participants'),2,'Registration history stores complete group');
  PERFORM assert_eq(jsonb_array_length(registration->'personIds'),2,'Registration history stores allocated stable IDs');
  PERFORM assert_true(NOT registration::text LIKE '%never-history%','Secret metadata excluded from registration snapshot');
  original_ids:=registration->'personIds';
  SELECT id INTO person FROM eshop.order_participants WHERE current_order_id=source
   AND answers#>>ARRAY['fields','0',field_id::text]='Original A';
  FOR regular IN SELECT id FROM eshop.orders WHERE form=(x->>'form')::bigint AND state<>'waitlisted' LOOP
   PERFORM public.update_order_and_tickets_to_storno_221(regular);
  END LOOP;
  w:=pg_temp.offer(x,source,CASE WHEN mode='split' THEN 1 ELSE 2 END);
  IF mode='split' THEN
   details:=pg_temp.checkout(x,ARRAY[person]);
  ELSE
   details:=pg_temp.checkout(x,ARRAY(SELECT id FROM eshop.order_participants WHERE current_order_id=source ORDER BY id));
  END IF;
  details:=jsonb_set(details,'{ticket}',(SELECT jsonb_agg(jsonb_set(ticket,'{fields}',ticket->'fields'||
    jsonb_build_array(jsonb_build_object(field_id::text,'Accepted updated answer')))) FROM jsonb_array_elements(details->'ticket') ticket));
  accept_cmd:=gen_random_uuid();
  result:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id',
   'personIds',(SELECT jsonb_agg(ticket->'participantId') FROM jsonb_array_elements(details->'ticket') ticket),
   'orderDetails',details),accept_cmd,gen_random_uuid(),(x->>'actor')::uuid);
  IF result#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Accept failed %',result; END IF;
  target:=(result#>>'{data,order,id}')::bigint;
  SELECT data INTO acceptance FROM eshop.orders_history WHERE "order"=source
   AND data->>'action'='waitlist_accept' AND data->>'commandId'=accept_cmd::text;
  PERFORM assert_eq(jsonb_array_length(acceptance->'participantsBefore'),2,'Pre-conversion group preserved');
  PERFORM assert_eq(jsonb_array_length(acceptance->'participantsAfter'),CASE WHEN mode='split' THEN 1 ELSE 0 END,'Source group shrinks explicitly');
  PERFORM assert_eq(jsonb_array_length(acceptance->'acceptedParticipants'),CASE WHEN mode='split' THEN 1 ELSE 2 END,'Target persons captured');
  PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(acceptance->'participantsBefore') p
   WHERE p->>'id'=person::text AND p#>>ARRAY['answers','fields','0',field_id::text]='Original A'),'Original selected answer survives acceptance overwrite');
  PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(acceptance->'acceptedParticipants') p
   WHERE p->>'id'=person::text AND p#>>ARRAY['answers','fields','0',field_id::text]='Accepted updated answer'),'Accepted updated answer captured independently');
  PERFORM assert_true(NOT acceptance::text LIKE '%never-history%','Secrets excluded from acceptance snapshots');
  PERFORM assert_eq((SELECT current_order_id FROM eshop.order_participants WHERE id=person),target,'Person moved to target');
  UPDATE eshop.order_participants SET answers='{"later":"edited after checkout"}' WHERE id=person;
  PERFORM assert_eq((SELECT data FROM eshop.orders_history WHERE id=source_history),registration,'Later person edits do not rewrite registration history');
  PERFORM assert_eq((SELECT data FROM eshop.orders_history WHERE "order"=source AND data->>'action'='waitlist_accept'
   AND data->>'commandId'=accept_cmd::text),acceptance,'Later edits do not rewrite acceptance history');
  IF mode='split' THEN
   PERFORM assert_eq((SELECT data FROM eshop.orders_history WHERE "order"=target AND data->>'action'='waitlist_accept'
    AND data->>'commandId'=accept_cmd::text),acceptance,'Linked child keeps same conversion snapshot');
  END IF;
 END LOOP;
END $$;
ROLLBACK;
