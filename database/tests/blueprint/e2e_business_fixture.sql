-- Only synthetic disposable setup. Commands under test remain canonical SQL.
CREATE OR REPLACE FUNCTION public.blueprint_seed_business_e2e_fixture(f jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE bp bigint:=(f->>'blueprint')::bigint; occ bigint:=(f->>'occasion')::bigint;
 fid bigint:=(f->>'form')::bigint; actor uuid:=(f->>'actor')::uuid;
 b eshop.blueprints; doc jsonb; changes jsonb:='[]'; names text[]:=ARRAY['Free standard','Free premium','Used ticket','Foreign hold','Own hold','Same order A','Same order B','Other order A','Other order B','Free spare','Unassigned'];
 name text; node uuid; group_id uuid:=gen_random_uuid(); empty_id uuid:=gen_random_uuid(); unknown_id uuid:=gen_random_uuid(); prod bigint; premium bigint; bank bigint; un bigint;
 nodes_map jsonb:='{}'; spots_map jsonb:='{}'; index int:=0; r jsonb; ord bigint; pay bigint; ticket bigint; opt bigint; amount numeric; member text; order_map jsonb:='{}';
 own_secret uuid:=gen_random_uuid(); foreign_secret uuid:=gen_random_uuid();
 inspector_type bigint; inspector_product bigint;
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned full E2E project required'; END IF;
 SELECT * INTO b FROM eshop.blueprints WHERE id=bp; IF b.layout IS NULL THEN RAISE EXCEPTION 'real persisted V2 fixture required'; END IF;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SELECT unit INTO un FROM public.occasions WHERE id=occ;
 UPDATE public.occasions SET features=features||'[{"code":"ticket","is_enabled":true,"ticket_type":"wide"}]'::jsonb WHERE id=occ AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(features) feature WHERE feature->>'code'='ticket');
 INSERT INTO eshop.bank_accounts(title,account_number,account_number_human_readable,type,is_fetch_enabled,supported_currencies) VALUES('Synthetic local bank','123456/0100','123456/0100','FIO',false,ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(un,bank,1);
 UPDATE public.forms SET bank_account=bank,data=coalesce(data,'{}')||'{"schedule":{"start_time":"2020-01-01T00:00:00Z","end_time":"2099-01-01T00:00:00Z"}}'::jsonb WHERE id=fid;
 UPDATE public.form_fields SET data=coalesce(data,'{}')||'{"max_tickets":20}' WHERE form=fid AND type='ticket';
 SELECT id INTO premium FROM eshop.products WHERE occasion=occ AND title='Premium chair';
 doc:=jsonb_set(b.layout,'{canvas}',b.layout->'canvas'||'{"width":1600,"height":1400}');
 doc:=jsonb_set(doc,'{nodes}',doc->'nodes'||jsonb_build_array(
  jsonb_build_object('id',group_id,'kind','group','label','Free and operated seats','width',1,'height',1,'transform',jsonb_build_object('x',0,'y',0,'rotation',0)),
  jsonb_build_object('id',empty_id,'kind','group','label','Empty group','width',1,'height',1,'transform',jsonb_build_object('x',0,'y',0,'rotation',0)),
  jsonb_build_object('id',unknown_id,'kind','group','label','Unknown default','width',1,'height',1,'transform',jsonb_build_object('x',0,'y',0,'rotation',0))));
 FOREACH name IN ARRAY names LOOP
  index:=index+1;node:=gen_random_uuid();prod:=CASE WHEN name='Unassigned' THEN NULL WHEN name IN ('Free premium','Same order B','Other order B') THEN premium ELSE (f->>'product')::bigint END;
  doc:=jsonb_set(doc,'{nodes}',doc->'nodes'||jsonb_build_array(jsonb_build_object('id',node,'kind','seat','label',name,'parentId',CASE WHEN name='Unassigned' THEN unknown_id ELSE group_id END,'width',40,'height',40,'transform',jsonb_build_object('x',100+((index-1)%5)*200,'y',950+((index-1)/5)*160,'rotation',0))));
  changes:=changes||jsonb_build_array(jsonb_build_object('nodeId',node,'spotId',NULL,'productId',prod,'title',name,'groupNodeId',CASE WHEN name='Unassigned' THEN unknown_id ELSE group_id END,'selectionUnitId',NULL,'blocked',false,'productAssignmentMode','override','operation','upsert'));
  nodes_map:=nodes_map||jsonb_build_object(name,node);
 END LOOP;
 r:=public.update_blueprint_client_sync_v1(jsonb_build_object('id',bp,'occasion',occ,'organization',b.organization,'title',b.title,'expected_layout_revision',b.layout_revision,'layout',doc,'textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(doc,occ)),'seatChanges',changes,'groupProductChanges',jsonb_build_array(jsonb_build_object('groupNodeId',group_id,'productId',(f->>'product')::bigint),jsonb_build_object('groupNodeId',empty_id,'productId',(f->>'product')::bigint)),'areaBindingChanges','[]'::jsonb),gen_random_uuid());
 IF r->>'status'<>'applied' THEN RAISE EXCEPTION 'business fixture save rejected: %',r; END IF;
 SELECT jsonb_object_agg(s.title,binding.spot) INTO spots_map FROM eshop.blueprint_seat_bindings binding JOIN eshop.spots s ON s.id=binding.spot WHERE binding.blueprint=bp;
 UPDATE eshop.spots SET secret=foreign_secret,secret_expiration_time=now()+interval '12 hours' WHERE id=(spots_map->>'Foreign hold')::bigint;
 UPDATE eshop.spots SET secret=own_secret,secret_expiration_time=now()+interval '12 hours' WHERE id=(spots_map->>'Own hold')::bigint;
 -- Seed known paid facts; all subsequent UI swap/replacement uses the real
 -- receipted command and payment recalculation, never fixture-side arithmetic.
 FOREACH name IN ARRAY ARRAY['Used ticket','Same order','Other order A','Other order B'] LOOP
  ord:=public.allocate_ticket_order_identity_internal(fid);
  amount:=CASE WHEN name='Same order' THEN 250 WHEN name='Other order B' THEN 150 ELSE 100 END;
  INSERT INTO eshop.payment_info(bank_account,amount,paid,currency_code,variable_symbol) VALUES(bank,amount,amount,'CZK',100000+ord) RETURNING id INTO pay;
  UPDATE eshop.orders SET state='paid',price=amount,currency_code='CZK',payment_info=pay,data=jsonb_build_object('name','Synthetic','surname',name,'email','blueprint@example.invalid','tickets','[]'::jsonb) WHERE id=ord;
  FOREACH member IN ARRAY CASE WHEN name='Same order' THEN ARRAY['Same order A','Same order B'] ELSE ARRAY[name] END LOOP
   SELECT product INTO prod FROM eshop.spots WHERE id=(spots_map->>member)::bigint;
   INSERT INTO eshop.tickets(occasion,state,note,note_hidden,ticket_symbol) VALUES(occ,CASE WHEN name='Used ticket' THEN 'used' ELSE 'paid' END,'Synthetic public fixture note','Synthetic private fixture note',public.generate_ticket_symbol(b.organization,occ)) RETURNING id INTO ticket;
   INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(ord,ticket,prod) RETURNING id INTO opt;
   UPDATE eshop.spots SET order_product_ticket=opt WHERE id=(spots_map->>member)::bigint;
   IF name='Used ticket' THEN
    INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Synthetic inspector extras','food') RETURNING id INTO inspector_type;
    INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(occ,inspector_type,'Synthetic complimentary extra',0,'CZK') RETURNING id INTO inspector_product;
    INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(ord,inspector_product,ticket);
   END IF;
   UPDATE eshop.orders SET data=jsonb_set(data,'{tickets}',data->'tickets'||jsonb_build_array(jsonb_build_object('id',ticket,'products',jsonb_build_array(public._swap_spots_generate_product_json(prod,(spots_map->>member)::bigint))))) WHERE id=ord;
  END LOOP;
  order_map:=order_map||jsonb_build_object(name,ord);
 END LOOP;
 UPDATE eshop.tickets SET ticket_symbol=public.generate_ticket_symbol(b.organization,occ) WHERE occasion=occ AND ticket_symbol IS NULL;
 RETURN f||jsonb_build_object('business',jsonb_build_object('nodeIds',nodes_map,'spotIds',spots_map,'orders',order_map,'ownSecret',own_secret,'emptyGroupNodeId',empty_id,'unknownGroupNodeId',unknown_id,'bankAccount',bank));
END $$;
