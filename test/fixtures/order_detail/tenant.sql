-- Task-owned synthetic review fixture. Never run on a production or shared DB.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE project='festapp-order-detail-20261101') THEN RAISE EXCEPTION 'Wrong review sandbox'; END IF;
 IF EXISTS(SELECT 1 FROM public.occasions WHERE link='order-detail-ples') THEN RAISE EXCEPTION 'Review fixture already exists - do not overwrite user edits'; END IF;
END $$;
SET festapp.email_wake='scheduled';
UPDATE public.email_capacity SET paused=true,worker_url=NULL;
DO $$
#variable_conflict use_variable
DECLARE f jsonb;req jsonb;doc jsonb;nodes jsonb:='[]';changes jsonb:='[]';units jsonb:='[]';
 actor uuid;oc bigint;un bigint;form_id bigint;bp bigint;prod bigint;bank bigint;pt bigint;extra bigint;standing bigint;
 node uuid;grp uuid;unit_id uuid;couch uuid;area uuid;pool bigint;ctx bigint;r jsonb;
 i int;j int;n int;oid bigint;pi bigint;tid bigint;iid bigint;spot bigint;ticket_data jsonb;tickets jsonb;price numeric;received numeric;name text;surname text;contact text;state text;message uuid;stock bigint;batch uuid;
 field_email bigint;field_phone bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal(1);actor:=(f->>'actor')::uuid;oc:=(f->>'occasion')::bigint;form_id:=(f->>'form')::bigint;bp:=(f->>'blueprint')::bigint;prod:=(f->>'product')::bigint;
 SELECT unit INTO un FROM public.occasions WHERE id=oc;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 UPDATE public.occasions SET title='Zimní ples v kulturním domě',link='order-detail-ples',start_time='2027-01-16 18:00+01',end_time='2027-01-17 03:00+01',
  features=(SELECT jsonb_agg(CASE WHEN v->>'code'='ticket' THEN v-'layout' ELSE v END) FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) v WHERE o.link='e2e-tabs-a' AND v->>'code' IN ('ticket','form'))||'[{"code":"blueprint","is_enabled":true},{"code":"deposit","is_enabled":true}]',data='{"timezone":"Europe/Prague"}' WHERE id=oc;
 PERFORM public.reserve_public_link_internal('occasion',oc,'order-detail-ples',true);
 UPDATE public.units SET title='Spolek přátel kultury' WHERE id=un;
 UPDATE public.forms SET title='Vstupenky na zimní ples' WHERE id=form_id;
 UPDATE eshop.products SET title='Vstup do hlavního sálu',price=650 WHERE id=prod;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Doplňky','other') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) VALUES(oc,pt,'Dětské menu',150,'CZK',false) RETURNING id INTO extra;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) SELECT oc,product_type,'Stání na balkoně',350,'CZK',false FROM eshop.products WHERE id=prod RETURNING id INTO standing;
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES(oc,'Balkon','generic',20) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Stání na balkoně') RETURNING id INTO ctx;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(standing,ctx,1);
 INSERT INTO eshop.bank_accounts(title,account_number,account_number_human_readable,type,supported_currencies,is_fetch_enabled) VALUES('Ukázkový účet spolku','123456/0100','123456/0100','FIO',ARRAY['CZK'],false) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(un,bank,1);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 INSERT INTO public.form_fields(form,title,type,is_ticket_field,"order",product_type) VALUES(form_id,'Doplňky','product_type',true,3,pt);
 INSERT INTO public.form_fields(form,title,type,is_ticket_field,"order") VALUES(form_id,'Kontaktní e-mail','email',false,1) RETURNING id INTO field_email;
 INSERT INTO public.form_fields(form,title,type,is_ticket_field,"order") VALUES(form_id,'Telefon','phone',false,2) RETURNING id INTO field_phone;
 req:=f->'request';doc:=req->'layout';
 FOR i IN 1..4 LOOP
  grp:=gen_random_uuid();
  nodes:=nodes||jsonb_build_array(jsonb_build_object('id',grp,'kind','group','label','Stůl '||i,'width',240,'height',180,'transform',jsonb_build_object('x',150+((i-1)%2)*420,'y',150+((i-1)/2)*300,'rotation',0)));
  FOR j IN 1..6 LOOP
   node:=gen_random_uuid();
   nodes:=nodes||jsonb_build_array(jsonb_build_object('id',node,'parentId',grp,'kind','seat','label',j::text,'width',40,'height',40,'transform',jsonb_build_object('x',((j-1)%3)*70-70,'y',CASE WHEN j<=3 THEN -60 ELSE 60 END,'rotation',0)));
   changes:=changes||jsonb_build_array(jsonb_build_object('productAssignmentMode','override','nodeId',node,'spotId',NULL,'productId',prod,'title','Místo '||j,'groupNodeId',grp,'selectionUnitId',NULL,'blocked',false,'operation','upsert'));
  END LOOP;
 END LOOP;
 couch:=gen_random_uuid();unit_id:=gen_random_uuid();
 nodes:=nodes||jsonb_build_array(jsonb_build_object('id',couch,'kind','group','label','Pohovka u pódia','width',180,'height',100,'transform',jsonb_build_object('x',400,'y',820,'rotation',0)));
 FOR j IN 1..2 LOOP
  node:=gen_random_uuid();
  nodes:=nodes||jsonb_build_array(jsonb_build_object('id',node,'parentId',couch,'kind','seat','label',j::text,'symbol','sofa','width',55,'height',40,'transform',jsonb_build_object('x',j*65-100,'y',0,'rotation',0)));
  units:=units||jsonb_build_array(node::text);
  changes:=changes||jsonb_build_array(jsonb_build_object('productAssignmentMode','override','nodeId',node,'spotId',NULL,'productId',prod,'title','Pohovka '||j,'groupNodeId',couch,'selectionUnitId',unit_id,'blocked',false,'operation','upsert'));
 END LOOP;
 area:=gen_random_uuid();
 nodes:=nodes||jsonb_build_array(jsonb_build_object('id',area,'kind','capacityArea','capacity',20,'width',180,'height',100,'transform',jsonb_build_object('x',800,'y',820,'rotation',0)));
 doc:=doc||jsonb_build_object('nodes',nodes,'selectionUnits',jsonb_build_array(jsonb_build_object('id',unit_id,'nodeIds',units,'kind','atomic')));
 req:=req||jsonb_build_object('title','Hlavní sál a balkon','layout',doc,'seatChanges',changes,
  'textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(doc,oc)),
  'areaBindingChanges',jsonb_build_array(jsonb_build_object('nodeId',area,'inventoryContextId',ctx,'productId',standing,'operation','upsert')));
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 IF r->>'status'<>'applied' THEN RAISE EXCEPTION 'Layout fixture rejected %',r; END IF;
 FOR i IN 1..8 LOOP
  name:=CASE i WHEN 1 THEN 'Jana' WHEN 2 THEN 'Petr' WHEN 3 THEN 'Alžběta' WHEN 4 THEN 'Eva' WHEN 5 THEN 'Martin' WHEN 6 THEN 'Klára' WHEN 7 THEN 'Tomáš' ELSE 'David' END;
  surname:=CASE i WHEN 1 THEN 'Novotná' WHEN 2 THEN 'Dvořák' WHEN 3 THEN 'Černá-Svobodová' WHEN 4 THEN 'Veselá' WHEN 5 THEN 'Kučera' WHEN 6 THEN 'Malá' WHEN 7 THEN 'Němec' ELSE 'Procházka' END;
  contact:=CASE i WHEN 1 THEN 'jana.chybny-kontakt@example.invalid' WHEN 3 THEN 'alzbeta.cerna-svobodova.dlouhy.kontakt@example.invalid' ELSE 'host'||i||'@example.invalid' END;
  n:=CASE i WHEN 1 THEN 4 WHEN 2 THEN 2 WHEN 3 THEN 6 WHEN 4 THEN 2 WHEN 5 THEN 3 ELSE 1 END;
  price:=CASE WHEN i=5 THEN n*350 ELSE n*650 END+CASE WHEN i=2 THEN 150 ELSE 0 END;
  received:=CASE i WHEN 3 THEN 1000 WHEN 6 THEN 0 ELSE price END;
  state:=CASE i WHEN 6 THEN 'ordered' WHEN 8 THEN 'storno' ELSE 'paid' END;
  INSERT INTO eshop.payment_info(amount,paid,returned,currency_code,bank_account,variable_symbol,deadline,deposit_amount,deposit_deadline)
   VALUES(price,received,CASE WHEN i=8 THEN price ELSE 0 END,'CZK',bank,270100+i,'2027-01-10 23:00+01',CASE WHEN i=3 THEN 1000 END,CASE WHEN i=3 THEN '2026-12-15 23:00+01'::timestamptz END) RETURNING id INTO pi;
  oid:=public.allocate_ticket_order_identity_internal(form_id);
  tickets:='[]';
  FOR j IN 1..n LOOP
   INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data) VALUES(oc,CASE WHEN i=7 THEN 'used' ELSE state END,'PLES-'||i||'-'||j,
    '{}'::jsonb) RETURNING id INTO tid;
   INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,CASE WHEN i=5 THEN standing ELSE prod END) RETURNING id INTO iid;
   IF i=5 THEN
    INSERT INTO eshop.spots(occasion,inventory_context,order_product_ticket,product,title,state) VALUES(oc,ctx,iid,standing,'Stání na balkoně','ordered');
   ELSIF i<>8 THEN
    SELECT s.id INTO spot FROM eshop.spots s JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
     WHERE s.blueprint=bp AND s.order_product_ticket IS NULL AND CASE WHEN i=4 THEN sb.group_node=couch ELSE sb.group_node<>couch END ORDER BY s.id LIMIT 1;
    UPDATE eshop.spots SET order_product_ticket=iid WHERE id=spot;
   END IF;
   ticket_data:=jsonb_build_object('id',tid,'ticket_symbol','PLES-'||i||'-'||j,'products',jsonb_build_array(jsonb_build_object('id',CASE WHEN i=5 THEN standing ELSE prod END,'title',CASE WHEN i=5 THEN 'Stání na balkoně' ELSE 'Vstup do hlavního sálu' END,'price',CASE WHEN i=5 THEN 350 ELSE 650 END,'currency_code','CZK')));
   IF i=2 AND j=1 THEN
    INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,extra);
    ticket_data:=jsonb_set(ticket_data,'{products}',ticket_data->'products'||jsonb_build_array(jsonb_build_object('id',extra,'title','Dětské menu','price',150,'currency_code','CZK')));
   END IF;
   tickets:=tickets||jsonb_build_array(ticket_data);
  END LOOP;
  UPDATE eshop.orders SET price=price,currency_code='CZK',state=state,payment_info=pi,
   note_hidden=CASE WHEN i=3 THEN 'Záloha přijata. Doplatek do 10. ledna.' END,
   data=jsonb_build_object('name',name,'surname',surname,'email',contact,'phone','+420 777 000 00'||i,'form',(SELECT key FROM public.forms WHERE id=form_id),'tickets',tickets,
    'fields',jsonb_build_array(jsonb_build_object(field_email::text,contact),jsonb_build_object(field_phone::text,'+420 777 000 00'||i))) WHERE id=oid;
  INSERT INTO eshop.orders_history("order",created_by,state,price,currency_code,data) SELECT id,actor,state,price,currency_code,data FROM eshop.orders WHERE id=oid;
  IF received>0 THEN
   INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,vs,transaction_type,created_by,ingest_source,message_for_recipient)
    VALUES(bank,pi,received,'CZK',now()-interval '2 days',(270100+i)::text,'manual',actor,'manual','Syntetický výchozí pohyb pro lokální ukázku');
  END IF;
  IF i=8 THEN
   INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,vs,transaction_type,created_by,ingest_source,message_for_recipient)
    VALUES(bank,pi,-price,'CZK',now()-interval '1 day',(270100+i)::text,'return',actor,'manual','Syntetické výchozí vrácení - žádná banka nebyla kontaktována');
  END IF;
  IF i IN(1,2,3,6) THEN
   PERFORM set_config('request.jwt.claim.role','service_role',true);
   message:=(public.enqueue_order_email(CASE WHEN i=6 THEN 'TICKET_ORDER_CONFIRMATION' ELSE 'ORDER_TICKETS' END,jsonb_build_object('order_id',oid),1,oc,un)->>'message_id')::uuid;
   UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now()-interval '1 day',delivered_at=CASE WHEN i<>6 THEN now()-interval '1 day' END,bounced_at=CASE WHEN i=6 THEN now()-interval '1 day' END WHERE message_id=message;
   PERFORM set_config('request.jwt.claim.role','authenticated',true);
  END IF;
 END LOOP;
 -- Second venue deliberately reuses a chair name: identity, not text, owns focus.
 -- All bootstrap delivery and ledger facts above are synthetic presentation scenarios.
END $$;
NOTIFY pgrst,'reload schema';
