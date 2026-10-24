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
-- The same field type can occur twice; stable IDs distinguish those answers
-- within each ticket, and each ticket retains its own product and note.
CREATE FUNCTION pg_temp.personal_ticket(x jsonb,who text,first_value text,second_value text,note_value text,product bigint DEFAULT NULL,person bigint DEFAULT NULL,modern boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE fields jsonb;
BEGIN
 fields:=CASE WHEN modern THEN jsonb_build_array(
  jsonb_build_object(x->>'nameField',who),jsonb_build_object(x->>'firstField',first_value),
  jsonb_build_object(x->>'secondField',second_value),jsonb_build_object(x->>'noteField',note_value))
 ELSE jsonb_build_array(jsonb_build_object('name',who,'_subFieldId',x->'nameField'),
  jsonb_build_object('text',first_value,'_subFieldId',x->'firstField'),
  jsonb_build_object('text',second_value,'_subFieldId',x->'secondField'),
  jsonb_build_object('note',note_value,'_subFieldId',x->'noteField')) END;
 IF product IS NOT NULL THEN fields:=fields||jsonb_build_array(jsonb_build_object('product_type',product::text,
  '_subFieldId',x->'productField','price',0.01,'currency_code','CZK')); END IF;
 RETURN jsonb_build_object('fields',fields)||CASE WHEN person IS NOT NULL THEN jsonb_build_object('ticketId',person) ELSE '{}' END;
END $$;
CREATE FUNCTION pg_temp.assert_ticket_person(x jsonb,oid bigint,who text,first_value text,second_value text,note_value text,product bigint,amount numeric)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE p record; snapshot jsonb;
BEGIN
 SELECT * INTO STRICT p FROM pg_temp.ticket_rows person WHERE person.current_order_id=oid
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(person.answers->'fields') field WHERE field->>(x->>'nameField')=who);
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(p.answers->'fields') f WHERE f->>(x->>'firstField')=first_value),'First text field remains bound to its own stable ID and person');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(p.answers->'fields') f WHERE f->>(x->>'secondField')=second_value),'Second field of the same text type remains distinct');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(p.answers->'fields') f WHERE f->>(x->>'noteField')=note_value),'Personal note answer remains distinct');
 SELECT ticket INTO STRICT snapshot FROM eshop.orders o CROSS JOIN LATERAL jsonb_array_elements(o.data->'tickets') ticket
  WHERE o.id=oid AND (ticket->>'id')::bigint=p.ticket_id;
 PERFORM assert_eq(snapshot->>'note',note_value,'Order.data ticket note matches its own person');
 PERFORM assert_eq((snapshot#>>'{products,0,id}')::bigint,product,'Order.data ticket product matches its own person');
 PERFORM assert_eq((snapshot#>>'{products,0,price}')::numeric,amount,'Each product gets its server price');
 PERFORM assert_eq((SELECT opt.product FROM eshop.order_product_ticket opt WHERE opt."order"=oid AND opt.ticket=p.ticket_id AND opt.product IS NOT NULL),product,'Live product row is linked to the correct ticket');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(4); name_id bigint; first_id bigint; second_id bigint; note_id bigint; product_field bigint; expensive bigint;
 legacy jsonb; modern jsonb; result jsonb; legacy_order bigint; modern_order bigint; source bigint; child bigint;
 p1 bigint; p2 bigint; w jsonb; person1_before jsonb; child_before jsonb; registration_before jsonb; child_history_before jsonb;
 source_history bigint; foreign_form bigint; foreign_text bigint; bad jsonb; order_count bigint;
BEGIN
 INSERT INTO form_fields(form,type,is_ticket_field,is_required,title) VALUES((x->>'form')::bigint,'name',true,true,'Name') RETURNING id INTO name_id;
 INSERT INTO form_fields(form,type,is_ticket_field,is_required,title) VALUES((x->>'form')::bigint,'text',true,true,'First custom text') RETURNING id INTO first_id;
 INSERT INTO form_fields(form,type,is_ticket_field,is_required,title) VALUES((x->>'form')::bigint,'text',true,true,'Second custom text') RETURNING id INTO second_id;
 INSERT INTO form_fields(form,type,is_ticket_field,is_required,title) VALUES((x->>'form')::bigint,'note',true,true,'Individual note') RETURNING id INTO note_id;
 SELECT id INTO product_field FROM form_fields WHERE form=(x->>'form')::bigint AND product_type=(x->>'type')::bigint;
 UPDATE form_fields SET is_ticket_field=true WHERE id=product_field;
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code) VALUES((x->>'type')::bigint,(x->>'occasion')::bigint,'Second option',200,'CZK') RETURNING id INTO expensive;
 x:=x||jsonb_build_object('nameField',name_id,'firstField',first_id,'secondField',second_id,'noteField',note_id,'productField',product_field);
 legacy:=jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',jsonb_build_array(
  pg_temp.personal_ticket(x,'Person One','Red','Small','Note One',(x->>'product')::bigint),
  pg_temp.personal_ticket(x,'Person Two','Blue','Large','Note Two',expensive)));
 modern:=jsonb_set(legacy,'{ticket}',jsonb_build_array(
  pg_temp.personal_ticket(x,'Person One','Red','Small','Note One',(x->>'product')::bigint,NULL,true),
  pg_temp.personal_ticket(x,'Person Two','Blue','Large','Note Two',expensive,NULL,true)));
 result:=public.create_ticket_order_internal_v1(legacy);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'Legacy group failed %',result; END IF;
 legacy_order:=(result#>>'{order,id}')::bigint;
 result:=public.create_ticket_order_internal_v1(modern);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'Modern group failed %',result; END IF;
 modern_order:=(result#>>'{order,id}')::bigint;
 FOREACH source IN ARRAY ARRAY[legacy_order,modern_order] LOOP
  PERFORM pg_temp.assert_ticket_person(x,source,'Person One','Red','Small','Note One',(x->>'product')::bigint,100);
  PERFORM pg_temp.assert_ticket_person(x,source,'Person Two','Blue','Large','Note Two',expensive,200);
  PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=source),300::numeric,'Group amount sums distinct per-ticket server prices');
  PERFORM assert_eq((SELECT count(*) FROM pg_temp.ticket_rows WHERE current_order_id=source),2::bigint,'Group has exactly two people');
 END LOOP;
 PERFORM assert_eq((SELECT jsonb_agg(answers ORDER BY answers::text) FROM pg_temp.ticket_rows WHERE current_order_id=legacy_order),
  (SELECT jsonb_agg(answers ORDER BY answers::text) FROM pg_temp.ticket_rows WHERE current_order_id=modern_order),'Both transports produce the same separate personal answer sets');
 -- Capacity is full. Registration holds independent original fields, without products.
 result:=public.execute_waitlist_command_client_sync_v1('register',jsonb_build_object('form',x->'key','email','regression@example.invalid','tickets',jsonb_build_array(
  pg_temp.personal_ticket(x,'Waiting One','Original Red','Original Small','Original Note One'),
  pg_temp.personal_ticket(x,'Waiting Two','Original Blue','Original Large','Original Note Two',NULL,NULL,true))),gen_random_uuid(),gen_random_uuid(),NULL,
  jsonb_build_array(pg_temp.delivery('waitlist_confirmation',encode(extensions.gen_random_bytes(32),'hex'))));
 IF result#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Waiting group failed %',result; END IF;
 source:=(result#>>'{data,order,id}')::bigint;
 SELECT id INTO p1 FROM pg_temp.ticket_rows p WHERE current_order_id=source AND EXISTS(SELECT 1 FROM jsonb_array_elements(p.answers->'fields') f WHERE f->>name_id::text='Waiting One');
 SELECT id INTO p2 FROM pg_temp.ticket_rows p WHERE current_order_id=source AND EXISTS(SELECT 1 FROM jsonb_array_elements(p.answers->'fields') f WHERE f->>name_id::text='Waiting Two');
 SELECT id,data INTO source_history,registration_before FROM eshop.orders_history WHERE "order"=source AND data->>'action'='waitlist_register';
 SELECT answers INTO person1_before FROM pg_temp.ticket_rows WHERE id=p1;
 PERFORM public.update_order_and_tickets_to_storno_221(legacy_order);
 PERFORM public.update_order_and_tickets_to_storno_221(modern_order);
 w:=pg_temp.offer(x,source,2);
 result:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','ticketIds',jsonb_build_array(p2),
  'orderDetails',jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',jsonb_build_array(
   pg_temp.personal_ticket(x,'Waiting Two','Edited Blue','Edited Large','Accepted Note Two',expensive,p2)))),gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid);
 IF result#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Partial group failed %',result; END IF;
 child:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_eq(result#>>'{data,conversion}','split','Person two gets a split order');
 PERFORM pg_temp.assert_ticket_person(x,child,'Waiting Two','Edited Blue','Edited Large','Accepted Note Two',expensive,200);
 PERFORM assert_eq((SELECT answers FROM pg_temp.ticket_rows WHERE id=p1),person1_before,'Accepting person two does not overwrite person one');
 PERFORM assert_eq((SELECT outcome FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid AND ticket_id=p1),'pending','Person one retains the other pending place');
 SELECT data INTO child_before FROM eshop.orders WHERE id=child;
 SELECT data INTO child_history_before FROM eshop.orders_history WHERE "order"=child AND data->>'action'='waitlist_accept';
 result:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','ticketIds',jsonb_build_array(p1),
  'orderDetails',jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',jsonb_build_array(
   pg_temp.personal_ticket(x,'Waiting One','Edited Red','Edited Small','Accepted Note One',(x->>'product')::bigint,p1,true)))),
  gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid);
 IF result#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Full remaining group failed %',result; END IF;
 PERFORM assert_eq(result#>>'{data,conversion}','in_place','Person one converts remaining source identity');
 PERFORM pg_temp.assert_ticket_person(x,source,'Waiting One','Edited Red','Edited Small','Accepted Note One',(x->>'product')::bigint,100);
 PERFORM assert_eq((SELECT data FROM eshop.orders WHERE id=child),child_before,'Full remaining acceptance never rewrites the previous child');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=child),200::numeric,'Previous child price remains independent');
 PERFORM assert_eq((SELECT data FROM eshop.orders_history WHERE "order"=child AND data->>'action'='waitlist_accept'),child_history_before,'Previous child acceptance snapshot stays immutable');
 PERFORM assert_eq((SELECT data FROM eshop.orders_history WHERE id=source_history),registration_before,'Original complete group history stays immutable');
 -- Exact metadata scope remains enforced even with two text fields of one type.
 INSERT INTO forms(occasion,link) VALUES((x->>'occasion')::bigint,gen_random_uuid()::text) RETURNING id INTO foreign_form;
 INSERT INTO form_fields(form,type,is_ticket_field) VALUES(foreign_form,'text',true) RETURNING id INTO foreign_text;
 SELECT count(*) INTO order_count FROM eshop.orders WHERE form=(x->>'form')::bigint;
 bad:=jsonb_set(legacy,'{ticket,0,fields,1,_subFieldId}',to_jsonb(foreign_text));
 result:=public.create_ticket_order_internal_v1(bad);
 PERFORM assert_eq(result->>'message','FORM_FIELD_SCOPE_MISMATCH','Foreign custom field ID cannot map by the shared text type');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE form=(x->>'form')::bigint),order_count,'Foreign custom field rejected without a new order');
END $$;
ROLLBACK;
