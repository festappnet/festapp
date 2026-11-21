-- test-setup: database/tests/blueprint/fixtures.sql
DO $$
DECLARE fixture jsonb; request jsonb; result jsonb; quote jsonb; replay jsonb; payload jsonb;
 occ bigint; org bigint; un bigint; fid bigint; bp bigint; seat_product bigint; standing bigint; standing_alt bigint;
 addon_type bigint; addon bigint; pool bigint; ctx bigint; area uuid:=gen_random_uuid(); bank bigint;
 seats bigint[]; seat bigint; dest bigint; oid bigint; tid bigint; link bigint; added bigint; pid bigint;
 command_id uuid:=gen_random_uuid(); previous jsonb; revision text; stale jsonb; source_symbol text; products jsonb; group_ticket bigint; grouped_tickets jsonb; name_field bigint; answers jsonb;
BEGIN
 PERFORM set_config('festapp.email_wake','scheduled',true);
 fixture:=public.blueprint_test_fixture_internal();
 request:=fixture->'request';
 occ:=(fixture->>'occasion')::bigint;
 org:=(request->>'organization')::bigint;
 fid:=(fixture->>'form')::bigint;
 bp:=(fixture->>'blueprint')::bigint;
 seat_product:=(fixture->>'product')::bigint;
 SELECT unit INTO un FROM public.occasions WHERE id=occ;
 PERFORM set_config('request.jwt.claim.sub',fixture->>'actor',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 UPDATE public.user_info SET organization=org WHERE id=(fixture->>'actor')::uuid;
 UPDATE public.occasions SET features='[{"code":"blueprint","is_enabled":true},{"code":"ticket","is_enabled":true}]' WHERE id=occ;
 INSERT INTO eshop.payment_method_policy_scopes(organization_id,preferred_method) VALUES(org,'bank');
 INSERT INTO eshop.organization_payment_method_policies(organization_id,method,enabled) VALUES(org,'bank',true);
 INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies) VALUES('Test only','123456/0100','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 UPDATE public.forms SET bank_account=bank,data=coalesce(data,'{}')||'{"payments":{"bankEnabled":true}}' WHERE id=fid;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,maximum)
 SELECT occasion,product_type,'Standing',80,'CZK',2 FROM eshop.products WHERE id=seat_product RETURNING id INTO standing;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code)
 SELECT occasion,product_type,'Other standing',85,'CZK' FROM eshop.products WHERE id=seat_product RETURNING id INTO standing_alt;
 INSERT INTO eshop.product_types(occasion,title) VALUES(occ,'Extras') RETURNING id INTO addon_type;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(occ,addon_type,'Cloakroom',15,'CZK') RETURNING id INTO addon;
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES(occ,'Standing','generic',2) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Standing') RETURNING id INTO ctx;
 INSERT INTO public.resources(inventory_pool,occasion,title,capacity) VALUES(pool,occ,'Standing supply',2);
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(standing,ctx,1);
 PERFORM public.adjust_spot_capacity_for_pool(pool);
 request:=jsonb_set(request,'{layout,nodes}',request#>'{layout,nodes}'||jsonb_build_array(jsonb_build_object(
   'id',area,'kind','capacityArea','width',100,'height',100,'transform',jsonb_build_object('x',400,'y',400,'rotation',0))));
 request:=jsonb_set(request,'{areaBindingChanges}',jsonb_build_array(jsonb_build_object(
   'nodeId',area,'productId',standing,'inventoryContextId',ctx,'operation','upsert','capacity',2)));
 request:=request||jsonb_build_object('textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(request->'layout',occ)));
 result:=public.update_blueprint_client_sync_v1(request,gen_random_uuid());
 PERFORM public.assert_eq(result->>'status','applied','the actual blueprint save publishes seat and standing: '||result::text);
 SELECT array_agg(s.id ORDER BY s.id) INTO seats FROM eshop.spots s WHERE s.blueprint=bp;
 seat:=seats[1]; dest:=seats[2];

 oid:=public.allocate_ticket_order_identity_internal(fid);
 payload:=jsonb_build_object('form',fixture->'formKey','email','admission@example.invalid','ticket',
   jsonb_build_array(jsonb_build_object('spot',seat,'fields',jsonb_build_array(jsonb_build_object('product_type',standing)))));
 result:=public.finalize_ticket_order_internal_v1(oid,payload);
 PERFORM public.assert_eq(result->>'errorCode','ADMISSION_MULTIPLE_PRODUCTS','checkout rejects seat plus explicit standing');
 payload:=jsonb_set(payload,'{ticket}',jsonb_build_array(jsonb_build_object('fields',
   jsonb_build_array(jsonb_build_object('product_type',standing),jsonb_build_object('product_type',standing_alt)))));
 result:=public.finalize_ticket_order_internal_v1(oid,payload);
 PERFORM public.assert_eq(result->>'errorCode','ADMISSION_MULTIPLE_PRODUCTS','checkout rejects two explicit standing products');
 payload:=jsonb_set(payload,'{ticket}',jsonb_build_array(jsonb_build_object('fields',
   jsonb_build_array(jsonb_build_object('product_type',standing),jsonb_build_object('product_type',standing)))));
 result:=public.finalize_ticket_order_internal_v1(oid,payload);
 PERFORM public.assert_eq(result->>'errorCode','ADMISSION_MULTIPLE_PRODUCTS','checkout rejects repeated product IDs');
 payload:=jsonb_set(payload,'{ticket}',jsonb_build_array(jsonb_build_object('spot',seat,'fields','[]'::jsonb)));
 result:=public.finalize_ticket_order_internal_v1(oid,payload);
 PERFORM public.assert_eq(result->>'code','200','one real seat orders normally: '||result::text);
 SELECT x.ticket,x.id,t.ticket_symbol INTO tid,link,source_symbol FROM eshop.order_product_ticket x
 JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=oid;
 SELECT payment_info INTO pid FROM eshop.orders WHERE id=oid;

 result:=public.get_products_for_ticket_all_available(tid);
 PERFORM public.assert_eq(result#>>'{data,0,id}',addon::text,'ordinary picker offers the custom add-on only');
 revision:=public.operator_order_revision_internal_v1(oid);
 SELECT jsonb_build_array(public.order_admin_placement_internal(oid),
   (SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM eshop.orders_history h WHERE h."order"=oid),
   (SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.email_messages m WHERE m.order_id=oid)) INTO previous;
 FOR products IN SELECT jsonb_array_elements(jsonb_build_array(
   jsonb_build_array(jsonb_build_object('id',seat_product,'price',100),jsonb_build_object('id',standing,'price',80)),
   jsonb_build_array(jsonb_build_object('id',seat_product,'price',100),jsonb_build_object('id',seat_product,'price',100)),
   '[]'::jsonb,jsonb_build_array(jsonb_build_object('id',standing,'price',80)))) LOOP
   BEGIN
     PERFORM public.update_ticket_products_wsv2(tid,products);
     RAISE EXCEPTION 'invalid admission edit succeeded';
   EXCEPTION WHEN raise_exception THEN
     PERFORM public.assert_eq(SQLERRM,'ADMISSION_CHANGE_REQUIRES_COMMAND','direct edit rejects changed identity or multiplicity');
   END;
 END LOOP;
 result:=public.update_ticket_products_client_sync_v1(tid,'[]',gen_random_uuid());
 PERFORM public.assert_eq(result#>>'{data,reason}','ADMISSION_CHANGE_REQUIRES_COMMAND','Client Sync shares the guard');
 BEGIN
   PERFORM public.manage_operator_order_v1(occ,org,un,oid,gen_random_uuid(),revision,'update',
     jsonb_build_object('note','must roll back','tickets',jsonb_build_array(jsonb_build_object('ticketId',tid,'products','[]'::jsonb))));
   RAISE EXCEPTION 'invalid operator edit succeeded';
 EXCEPTION WHEN raise_exception THEN
   PERFORM public.assert_eq(SQLERRM,'ADMISSION_CHANGE_REQUIRES_COMMAND','operator batch shares the guard');
 END;
 PERFORM public.assert_eq(public.operator_order_revision_internal_v1(oid),revision,'rejection preserves order, ticket, payment and line revision');
 PERFORM public.assert_eq(jsonb_build_array(public.order_admin_placement_internal(oid),
   (SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM eshop.orders_history h WHERE h."order"=oid),
   (SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.email_messages m WHERE m.order_id=oid)),previous,
   'rejection preserves placement, history and delivery intents');
 result:=public.update_ticket_products_wsv2(tid,jsonb_build_array(
   jsonb_build_object('id',seat_product,'price',90),jsonb_build_object('id',addon,'price',15)));
 PERFORM public.assert_eq(result->>'code','200','existing admission repricing and add-ons still work');
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=seat),link,'existing placement keeps its relation');

 result:=public.get_order_admission_options_v1(oid,NULL);
 PERFORM public.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(result#>'{data,options}') opt
   WHERE opt->>'productId'=standing::text),'add options include the configured standing area');
 payload:=jsonb_build_object('productId',standing);
 quote:=public.preview_order_admission_change_v1(oid,NULL,payload,'[]');
 PERFORM public.assert_eq(quote#>>'{data,ticketCount}','2','quote shows separate ticket: '||quote::text);
 PERFORM public.assert_eq((quote#>>'{data,total}')::numeric,185::numeric,'quote uses saved and catalog prices');
 result:=public.confirm_order_admission_change_v1(oid,NULL,payload,'[]',quote#>>'{data,fingerprint}',command_id);
 PERFORM public.assert_eq(result->>'status','applied','addition confirms: '||result::text);
 replay:=public.confirm_order_admission_change_v1(oid,NULL,payload,'[]',quote#>>'{data,fingerprint}',command_id);
 PERFORM public.assert_eq(replay,result,'receipt returns the original ticket and effects');
 added:=(result#>>'{data,ticketIds,0}')::bigint;
 PERFORM public.assert_true(added IS NOT NULL AND added<>tid,'added visitor has separate ticket');
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=seat),link,'addition preserves original seat');
 PERFORM public.assert_eq((SELECT price FROM eshop.orders WHERE id=oid),185::numeric,'addition reprices order once');

 quote:=public.preview_order_admission_change_v1(oid,tid,payload,'[]');
 PERFORM public.assert_eq((quote#>>'{data,priceDelta}')::numeric,-10::numeric,'partial refund appears as a reduction');
 result:=public.confirm_order_admission_change_v1(oid,tid,payload,'[]',quote#>>'{data,fingerprint}',gen_random_uuid());
 PERFORM public.assert_eq(result->>'status','applied','seat to standing changes one admission: '||result::text);
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=seat),NULL::bigint,'moving releases original seat');
 PERFORM public.assert_eq((SELECT count(*) FROM eshop.spots WHERE inventory_context=ctx AND order_product_ticket IS NOT NULL),2::bigint,
   'standing now contains two distinct allocations');
 PERFORM public.assert_eq((SELECT ticket_symbol FROM eshop.tickets WHERE id=tid),source_symbol,'move preserves ticket code');
 BEGIN
   PERFORM public.update_ticket_products_wsv2(tid,jsonb_build_array(jsonb_build_object('id',seat_product,'price',90)));
   RAISE EXCEPTION 'stale edit restored the seat';
 EXCEPTION WHEN raise_exception THEN
   PERFORM public.assert_eq(SQLERRM,'ADMISSION_CHANGE_REQUIRES_COMMAND','stale editor cannot revert admission');
 END;
 result:=public.preview_order_admission_change_v1(oid,NULL,payload,'[]');
 PERFORM public.assert_eq(result#>>'{data,reason}','PRODUCT_CAPACITY_EXCEEDED','standing sells out');

 payload:=jsonb_build_object('productId',seat_product,'spotId',dest);
 quote:=public.preview_order_admission_change_v1(oid,tid,payload,'[]');
 PERFORM public.assert_eq((quote#>>'{data,priceDelta}')::numeric,20::numeric,'return to seat previews surcharge');
 UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=clock_timestamp()+interval '5 min' WHERE id=dest;
 stale:=public.confirm_order_admission_change_v1(oid,tid,payload,'[]',quote#>>'{data,fingerprint}',gen_random_uuid());
 PERFORM public.assert_eq(stale#>>'{data,reason}','BLUEPRINT_SEAT_UNAVAILABLE','late checkout hold blocks move');
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=dest;
 quote:=public.preview_order_admission_change_v1(oid,tid,payload,'[]');
 result:=public.confirm_order_admission_change_v1(oid,tid,payload,'[]',quote#>>'{data,fingerprint}',gen_random_uuid());
 PERFORM public.assert_eq(result->>'status','applied','standing to seat confirms: '||result::text);
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=dest),link,'new seat uses original link');
 PERFORM public.assert_eq((SELECT count(*) FROM eshop.spots WHERE inventory_context=ctx AND order_product_ticket IS NOT NULL),1::bigint,
   'moving releases only its own standing capacity');
 PERFORM public.assert_eq((SELECT amount FROM eshop.payment_info WHERE id=pid),195::numeric,'payment expectation tracks the final price');

 payload:=jsonb_build_object('productId',seat_product,'spotId',seat);
 quote:=public.preview_order_admission_change_v1(oid,tid,payload,'[]');
 PERFORM public.assert_eq((quote#>>'{data,priceDelta}')::numeric,0::numeric,'same product keeps sold price');
 result:=public.confirm_order_admission_change_v1(oid,tid,payload,'[]',quote#>>'{data,fingerprint}',gen_random_uuid());
 PERFORM public.assert_eq(result->>'status','applied','same product uses seating assignment: '||result::text);
 -- A malformed old order still shows both bought products and its recorded seat.
 BEGIN
   INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,standing);
   UPDATE eshop.orders SET data=jsonb_set(data,'{tickets,0,products}',(data#>'{tickets,0,products}')||
     jsonb_build_array(jsonb_build_object('id',standing,'price',80,'type','spot'))) WHERE id=oid;
   result:=public.get_products_for_ticket(tid);
   PERFORM public.assert_eq(result#>>'{data,admission,spotCount}','2','grid bundle detects both historical admission products: '||result::text);
   PERFORM public.assert_eq(result#>>'{data,canEdit}','false','ambiguous ticket is read-only');
   result:=public.get_order_admin_detail(oid,occ);
   PERFORM public.assert_eq(result#>>'{data,tickets,0,admission,reason}','ADMISSION_DATA_AMBIGUOUS','order detail exposes the same conflict');
   PERFORM public.assert_eq(result#>>'{data,places,0,active}','false','ambiguous placement is recorded without confirmation');
   RAISE SQLSTATE 'FA001';
 EXCEPTION WHEN SQLSTATE 'FA001' THEN NULL;
 END;
 UPDATE eshop.tickets SET state='used' WHERE id=tid;
 result:=public.preview_order_admission_change_v1(oid,tid,jsonb_build_object('productId',standing),'[]');
 PERFORM public.assert_eq(result#>>'{data,reason}','USED_TICKET_PROTECTED','used ticket cannot move');
 UPDATE eshop.tickets SET state='ordered' WHERE id=tid;

 -- Moving between different addressed products must use the canonical swap
 -- with a free destination, preserving the same holder.
 UPDATE eshop.spots SET product=standing_alt WHERE id=dest;
 payload:=jsonb_build_object('productId',standing_alt,'spotId',dest);
 quote:=public.preview_order_admission_change_v1(oid,tid,payload,'[]');
 PERFORM public.assert_eq((quote#>>'{data,priceDelta}')::numeric,-15::numeric,'different seat product quotes the price difference: '||quote::text);
 result:=public.confirm_order_admission_change_v1(oid,tid,payload,'[]',quote#>>'{data,fingerprint}',gen_random_uuid());
 PERFORM public.assert_eq(result->>'status','applied','different seat product uses the existing swap: '||result::text);
 PERFORM public.assert_eq((SELECT order_product_ticket FROM eshop.spots WHERE id=dest),link,'canonical swap preserves line identity');

 -- The existing selected unit owns quantity; each member receives its own answer.
 payload:=jsonb_build_object('productId',standing);
 quote:=public.preview_order_admission_change_v1(oid,tid,payload,'[]');
 result:=public.confirm_order_admission_change_v1(oid,tid,payload,'[]',quote#>>'{data,fingerprint}',gen_random_uuid());
 PERFORM public.assert_eq(result->>'status','applied','release both seats of the next target unit');
 UPDATE eshop.spots SET product=seat_product WHERE id=dest;
 UPDATE eshop.blueprint_seat_bindings SET selection_unit='178b5ee2-c218-4791-b72a-fe858156eaa9' WHERE spot=ANY(seats[3:4]);
 UPDATE eshop.blueprint_seat_bindings SET selection_unit='61e16de2-930b-4b0c-81e9-d4edb8844813' WHERE spot=ANY(seats[1:2]);
 INSERT INTO public.form_fields(form,type,title,is_ticket_field,is_required,is_hidden)
   VALUES(fid,'name','Jméno účastníka',true,true,false) RETURNING id INTO name_field;
 answers:=jsonb_build_array(
   jsonb_build_array(jsonb_build_object('_subFieldId',name_field::text,'name','Lenka')),
   jsonb_build_array(jsonb_build_object('_subFieldId',name_field::text,'name','Roman')));
 payload:=jsonb_build_object('productId',seat_product,'spotId',seats[3]);
 result:=public.preview_order_admission_change_v1(oid,NULL,payload,'[[],[]]');
 PERFORM public.assert_eq(result#>>'{data,reason}','REQUIRED_FIELD_MISSING','required answers apply to both group members');
 quote:=public.preview_order_admission_change_v1(oid,NULL,payload,answers);
 PERFORM public.assert_eq(quote#>>'{data,quantity}','2','review confirms the whole unit: '||quote::text);
 result:=public.confirm_order_admission_change_v1(oid,NULL,payload,answers,quote#>>'{data,fingerprint}',gen_random_uuid());
 PERFORM public.assert_eq(result->>'status','applied','whole unit addition confirms: '||result::text);
 grouped_tickets:=result#>'{data,ticketIds}';
 group_ticket:=(grouped_tickets->>0)::bigint;
 PERFORM public.assert_eq(jsonb_array_length(grouped_tickets),2,'whole unit purchase issues two distinct admissions');
 PERFORM public.assert_eq((SELECT data#>>ARRAY['fields','0',name_field::text] FROM eshop.tickets WHERE id=group_ticket),'Lenka','each ticket saves its own answer');
 PERFORM public.assert_eq((SELECT data#>>ARRAY['fields','0',name_field::text] FROM eshop.tickets WHERE id=(grouped_tickets->>1)::bigint),'Roman','second ticket saves the second answer');
 payload:=jsonb_build_object('productId',seat_product,'spotId',seats[1]);
 quote:=public.preview_order_admission_change_v1(oid,group_ticket,payload,'[]');
 PERFORM public.assert_eq(quote#>>'{data,quantity}','2','move reviews the entire source and destination unit: '||quote::text);
 result:=public.confirm_order_admission_change_v1(oid,group_ticket,payload,'[]',quote#>>'{data,fingerprint}',gen_random_uuid());
 PERFORM public.assert_eq(result->>'status','applied','whole unit uses the existing assignment owner: '||result::text);
 PERFORM public.assert_eq(result#>'{data,ticketIds}',grouped_tickets,'whole unit keeps both identities');
 PERFORM public.assert_eq((SELECT count(*) FROM eshop.spots WHERE id=ANY(seats[3:4]) AND order_product_ticket IS NOT NULL),0::bigint,
   'move releases both old seats');
 UPDATE eshop.payment_info SET payment_method='cash',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL WHERE id=pid;
 result:=public.preview_order_admission_change_v1(oid,NULL,jsonb_build_object('productId',standing),'[]');
 PERFORM public.assert_eq(result#>>'{data,reason}','ORDER_ADMISSION_UNAVAILABLE','unsupported payment mode cannot add a ticket');
END $$;
