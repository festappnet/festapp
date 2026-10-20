-- Exercises the same anonymous command, selection and finalizer as public forms.
-- Transaction-local data and scheduled email wake prevent external delivery.
BEGIN;
SELECT set_config('festapp.email_wake','scheduled',true);
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','anon',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; fid bigint; fk uuid; bank bigint;
 pt bigint; prod bigint; bp bigint; seat bigint; other_seat bigint; seat_field bigint;
 email_field bigint; name_field bigint; secret uuid:=gen_random_uuid(); client_id uuid:=gen_random_uuid();
 node_a uuid:=gen_random_uuid(); node_b uuid:=gen_random_uuid();
 payload jsonb; result jsonb; oid bigint; before_orders bigint; command uuid;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Seat checkout regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Seat checkout regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time)
 VALUES('Seat checkout regression',un,org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
 VALUES('Regression bank','FIO','123/0100',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.blueprints(title,organization,occasion,objects)
 VALUES('Regression seats',org,oc,'[]') RETURNING id INTO bp;
 INSERT INTO public.forms(occasion,link,is_open,blueprint,bank_account)
 VALUES(oc,gen_random_uuid()::text,true,bp,bank) RETURNING id,key INTO fid,fk;
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion,is_hidden)
 VALUES('Admission',pt,150,'CZK',oc,false) RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,type,product_type) VALUES(fid,'ticket',pt);
 INSERT INTO public.form_fields(form,type,is_required,is_hidden,is_ticket_field)
 VALUES(fid,'spot',true,false,true) RETURNING id INTO seat_field;
 INSERT INTO public.form_fields(form,type,is_required,is_hidden,is_ticket_field)
 VALUES(fid,'email',true,false,false) RETURNING id INTO email_field;
 INSERT INTO public.form_fields(form,type,is_required,is_hidden,is_ticket_field)
 VALUES(fid,'name',true,false,true) RETURNING id INTO name_field;
 INSERT INTO eshop.spots(title,product,occasion,blueprint)
 VALUES('A1',prod,oc,bp) RETURNING id INTO seat;
 INSERT INTO eshop.spots(title,product,occasion,blueprint)
 VALUES('A2',prod,oc,bp) RETURNING id INTO other_seat;
 -- Public holds require the same canonical physical bindings as the renderer.
 UPDATE eshop.blueprints SET layout_revision=1,layout=jsonb_build_object(
  'schemaVersion',2,'symbolSetVersion',1,
  'canvas',jsonb_build_object('x',0,'y',0,'width',400,'height',400,'fill','#FFFFFFFF'),
  'styles','{}'::jsonb,'seatingDefaults','{}'::jsonb,
  'textPolicy',jsonb_build_object('language','und','direction','auto'),
  'nodes',jsonb_build_array(
   jsonb_build_object('id',node_a,'kind','seat','width',48,'height',48,'transform',jsonb_build_object('x',100,'y',200,'rotation',0)),
   jsonb_build_object('id',node_b,'kind','seat','width',48,'height',48,'transform',jsonb_build_object('x',200,'y',200,'rotation',0))),
  'selectionUnits','[]'::jsonb) WHERE id=bp;
 PERFORM public.validate_blueprint_layout_internal((SELECT layout FROM eshop.blueprints WHERE id=bp));
 INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot) VALUES(bp,node_a,seat),(bp,node_b,other_seat);
 result:=public.select_spot(fk,secret,seat,true);
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'Seat selection failed: %',result; END IF;
 payload:=jsonb_build_object('form',fk,'secret',secret,
  'fields',jsonb_build_array(jsonb_build_object(email_field::text,'regression@example.invalid')),
  'ticket',jsonb_build_array(jsonb_build_object('spot',seat,'fields',
    jsonb_build_array(jsonb_build_object(name_field::text,'Test')))));
 SELECT count(*) INTO before_orders FROM eshop.orders WHERE form=fid;
 -- Every participant needs a seat, including the second ticket in a group.
 result:=public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{ticket}',
  (payload->'ticket')||jsonb_build_array((payload#>'{ticket,0}')-'spot')),gen_random_uuid(),client_id);
 IF result#>>'{data,errorCode}' IS DISTINCT FROM 'REQUIRED_FIELD_MISSING'
 OR (result#>>'{data,fieldId}')::bigint<>seat_field THEN RAISE EXCEPTION 'Missing second seat not rejected: %',result; END IF;
 -- A filled required seat must not bypass other required personal answers.
 result:=public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{ticket,0,fields}','[]'),gen_random_uuid(),client_id);
 IF result#>>'{data,errorCode}' IS DISTINCT FROM 'REQUIRED_FIELD_MISSING'
 OR (result#>>'{data,fieldId}')::bigint<>name_field THEN RAISE EXCEPTION 'Missing name not rejected: %',result; END IF;
 -- Passing presence validation must still enforce reservation ownership.
 result:=public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{secret}',to_jsonb(gen_random_uuid())),gen_random_uuid(),client_id);
 IF result#>>'{data,code}' IS DISTINCT FROM '1009' THEN RAISE EXCEPTION 'Wrong reservation secret not rejected: %',result; END IF;
 IF (SELECT count(*) FROM eshop.orders WHERE form=fid)<>before_orders THEN RAISE EXCEPTION 'Rejected checkout left an order'; END IF;
 command:=gen_random_uuid();
 result:=public.create_ticket_order_client_sync_v1(payload,command,client_id);
 IF result#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Selected seat checkout failed: %',result; END IF;
 oid:=(result#>>'{data,order,id}')::bigint;
 IF NOT EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
  JOIN eshop.tickets t ON t.id=x.ticket WHERE s.id=seat AND x."order"=oid AND x.product=prod AND t.state='ordered'
  AND t.ticket_symbol IS NOT NULL) THEN RAISE EXCEPTION 'Selected seat not bound to ordered ticket'; END IF;
 IF (SELECT price FROM eshop.orders WHERE id=oid)<>150 THEN RAISE EXCEPTION 'Seat price mismatch'; END IF;
 -- Idempotent replay must return the same order and avoid duplicate admissions.
 result:=public.create_ticket_order_client_sync_v1(payload,command,client_id);
 IF (result#>>'{data,order,id}')::bigint<>oid OR (SELECT count(*) FROM eshop.orders WHERE form=fid)<>before_orders+1 THEN
  RAISE EXCEPTION 'Checkout replay duplicated the order'; END IF;
 result:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),client_id);
 IF result#>>'{data,code}' IS DISTINCT FROM '1008' THEN RAISE EXCEPTION 'Occupied seat not rejected: %',result; END IF;
 RAISE NOTICE 'PASS: anonymous selected-seat checkout, required answers, ownership, occupancy and replay';
END $$;
ROLLBACK;
