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
DECLARE x jsonb:=pg_temp.fixture(2); name_id bigint; surname_id bigint; product_field_id bigint; r jsonb; payload jsonb;
 source bigint; w jsonb; ids uuid[]; person uuid; details jsonb; selected jsonb; first_answers jsonb; second_answers jsonb; offer_bundle jsonb;
BEGIN
 INSERT INTO form_fields(form,type,is_ticket_field,is_required) VALUES((x->>'form')::bigint,'name',true,true) RETURNING id INTO name_id;
 INSERT INTO form_fields(form,type,is_ticket_field,is_required) VALUES((x->>'form')::bigint,'surname',true,true) RETURNING id INTO surname_id;
 SELECT id INTO product_field_id FROM form_fields WHERE form=(x->>'form')::bigint AND product_type=(x->>'type')::bigint;
 UPDATE form_fields SET is_ticket_field=true WHERE id=product_field_id;
 FOR i IN 1..2 LOOP
  details:=pg_temp.checkout(x);
  details:=jsonb_set(details,'{ticket,0,fields}',details#>'{ticket,0,fields}'||jsonb_build_array(
   jsonb_build_object(name_id::text,'Regular'),jsonb_build_object(surname_id::text,'Fill')));
  r:=public.create_ticket_order_internal_v1(details);
  IF r->>'code'<>'200' THEN RAISE EXCEPTION 'Fill failed %',r; END IF;
 END LOOP;
 payload:=jsonb_build_object('form',x->'key','email','regression@example.invalid','people',jsonb_build_array(
  jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('name','Waiting','_subFieldId',name_id),jsonb_build_object('surname','One','_subFieldId',surname_id))),
  jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(name_id::text,'Waiting'),jsonb_build_object(surname_id::text,'One')))));
 r:=public.execute_waitlist_command_client_sync_v1('register',payload,gen_random_uuid(),gen_random_uuid(),NULL,
  jsonb_build_array(pg_temp.delivery('waitlist_confirmation',encode(extensions.gen_random_bytes(32),'hex'))));
 IF r#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Register failed %',r; END IF;
 source:=(r#>>'{data,order,id}')::bigint;
 SELECT array_agg(id ORDER BY id) INTO ids FROM eshop.order_participants WHERE current_order_id=source;
 PERFORM assert_eq((SELECT answers FROM eshop.order_participants WHERE id=ids[1]),(SELECT answers FROM eshop.order_participants WHERE id=ids[2]),'Waitlist registration aliases project to identical canonical answers');
 FOR person IN SELECT p.id FROM eshop.order_participants p JOIN eshop.orders o ON o.id=p.current_order_id WHERE o.form=(x->>'form')::bigint AND o.state<>'waitlisted' LOOP
  PERFORM public.update_order_and_tickets_to_storno_221((SELECT current_order_id FROM eshop.order_participants WHERE id=person));
 END LOOP;
 w:=pg_temp.offer(x,source,2);
 -- Existing pre-normalization rows must also be read without transport aliases.
 UPDATE eshop.order_participants SET answers=jsonb_build_object('fields',jsonb_build_array(
  jsonb_build_object(name_id::text,'Waiting','name','Waiting','_subFieldId',name_id),
  jsonb_build_object(surname_id::text,'One','surname','One','_subFieldId',surname_id))) WHERE id=ids[1];
 offer_bundle:=public.get_waitlist_offer_form(NULL,(w->>'id')::uuid);
 PERFORM assert_eq(offer_bundle->>'code','200','Authorized offer bundle loads');
 PERFORM assert_true(NOT (offer_bundle->'participants')::text LIKE '%_subFieldId%' AND NOT (offer_bundle->'participants')::text LIKE '%"name"%',
  'Offer participant DTO excludes transport aliases and internal metadata');
 FOR i IN 1..2 LOOP
  person:=ids[i];
  details:=pg_temp.checkout(x,ARRAY[person]);
  selected:=CASE WHEN i=1 THEN jsonb_build_array(jsonb_build_object('name','Waiting','_subFieldId',name_id),jsonb_build_object('surname','One','_subFieldId',surname_id))
   ELSE jsonb_build_array(jsonb_build_object(name_id::text,'Waiting'),jsonb_build_object(surname_id::text,'One')) END;
  selected:=selected||jsonb_build_array(jsonb_build_object('product_type',x->>'product','_subFieldId',product_field_id,'price',0.01,'currency_code','CZK'));
  details:=jsonb_set(details,'{ticket,0,fields}',selected);
  r:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','personIds',jsonb_build_array(person),'orderDetails',details),
   gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid);
  IF r#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Acceptance failed %',r; END IF;
  PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=(r#>>'{data,order,id}')::bigint),100::numeric,'Product price hint cannot alter ordinary acceptance pricing');
 END LOOP;
 SELECT answers INTO first_answers FROM eshop.order_participants WHERE id=ids[1];
 SELECT answers INTO second_answers FROM eshop.order_participants WHERE id=ids[2];
 PERFORM assert_eq(first_answers,second_answers,'Legacy and modern offer acceptance store identical canonical personal answers');
 PERFORM assert_eq(jsonb_array_length(first_answers->'fields'),2,'Product selections do not become personal answers');
 PERFORM assert_true(NOT first_answers::text LIKE '%_subFieldId%' AND NOT first_answers::text LIKE '%product_type%' AND NOT first_answers::text LIKE '%"name"%',
  'Accepted ledger answers contain stable personal field IDs only');
END $$;
ROLLBACK;
