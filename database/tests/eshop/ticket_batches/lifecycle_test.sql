BEGIN;
CREATE FUNCTION pg_temp.fixture(cap integer DEFAULT 1) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; un bigint; oc bigint; f bigint; fk uuid; pt bigint; prod bigint; bank bigint; actor uuid; suffix text:=gen_random_uuid()::text;
BEGIN
 INSERT INTO organizations(title) VALUES('Waitlist regression '||suffix) RETURNING id INTO org;
 INSERT INTO units(title,organization) VALUES('Waitlist regression',org) RETURNING id INTO un;
 INSERT INTO occasions(title,unit,organization,link,start_time,end_time) VALUES('Waitlist regression',un,org,suffix,now(),now()+interval '1 day') RETURNING id INTO oc;
 PERFORM public.reserve_public_link_internal('occasion',oc,suffix,true);
 INSERT INTO forms(occasion,link,participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds) VALUES(oc,suffix,cap,cap IS NOT NULL,CASE WHEN cap IS NOT NULL THEN 3600 END) RETURNING id,key INTO f,fk;
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Regression bank','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('spot','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion) VALUES('Admission',pt,100,'CZK',oc) RETURNING id INTO prod;
 INSERT INTO form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 actor:=gen_random_uuid();
 INSERT INTO auth.users(id,email) VALUES(actor,actor::text||'@example.invalid');
 INSERT INTO public.user_info(id,email_readonly,organization) VALUES(actor,actor::text||'@example.invalid',org);
 INSERT INTO occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor) VALUES(oc,actor,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 RETURN jsonb_build_object('organization',org,'unit',un,'occasion',oc,'form',f,'key',fk,'type',pt,'product',prod,'actor',actor,'link',suffix);
END $$;
CREATE FUNCTION pg_temp.checkout(x jsonb,tickets bigint[] DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',
 CASE WHEN tickets IS NULL THEN jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))
 ELSE (SELECT jsonb_agg(jsonb_build_object('ticketId',id,'fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))) FROM unnest(tickets) id) END);
$$;

CREATE FUNCTION pg_temp.reject_batch_sale() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF TG_TABLE_NAME='orders_history' AND NEW.state='paid' AND NEW.data ? 'batchId' THEN RAISE EXCEPTION 'injected_after_pairing'; END IF;
 RETURN NEW;
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(10); r jsonb; b uuid; oid bigint; sold bigint; ids bigint[]; original_opts bigint[];
 claim jsonb; part record; cmd uuid:=gen_random_uuid(); replay jsonb; report jsonb; pool_id bigint; context_id bigint; resource_id bigint; allocation_before jsonb; email_cmd uuid:=gen_random_uuid(); email_order bigint;
BEGIN
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES((x->>'unit')::bigint,(x->>'actor')::uuid,true);
 UPDATE public.user_info SET organization=(x->>'organization')::bigint WHERE id=(x->>'actor')::uuid;
 UPDATE public.occasions SET features=jsonb_build_array(jsonb_build_object('code','ticket','is_enabled',true,'ticket_type','wide','layout','{"schemaVersion":3,"templates":{"wide":{"page":{"width":595.28,"height":841.89},"ticketArea":{"x":29.76400000000001,"y":29.764,"width":535.752,"height":267.876},"elements":[{"id":"qr","binding":"qr","box":{"x":405.16245,"y":140.63490000000002,"width":80.3628,"height":80.3628},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"left"}},{"id":"ticketSymbol","binding":"ticketSymbol","box":{"x":405.16245,"y":224.9977,"width":80.3628,"height":22},"visible":true,"locked":false,"style":{"fontSize":9.375659999999998,"minFontSize":6,"maxLines":1,"color":"2A2A2A","align":"left"}},{"id":"spotGroup","binding":"spotGroup","box":{"x":50,"y":167.87599999999998,"width":241.08839999999998,"height":21},"visible":true,"locked":false,"style":{"fontSize":8.036279999999998,"minFontSize":6,"maxLines":1,"color":"2A2A2A","align":"left"}},{"id":"note","binding":"note","box":{"x":50,"y":211.87599999999998,"width":241.08839999999998,"height":21},"visible":true,"locked":false,"style":{"fontSize":8.036279999999998,"minFontSize":6,"maxLines":1,"color":"2A2A2A","align":"left"}},{"id":"price","binding":"price","box":{"x":50,"y":233.87599999999998,"width":241.08839999999998,"height":21},"visible":true,"locked":false,"style":{"fontSize":8.036279999999998,"minFontSize":6,"maxLines":1,"color":"2A2A2A","align":"left"}}]},"named":{"page":{"width":212.5,"height":387.5},"ticketArea":{"x":6.25,"y":6.25,"width":200,"height":375},"elements":[{"id":"logo","binding":"logo","box":{"x":71.875,"y":12.5,"width":56.25,"height":56.25},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"occasionTitle","binding":"occasionTitle","box":{"x":6.25,"y":77,"width":187.5,"height":32},"visible":true,"locked":false,"style":{"fontSize":12.5,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"occasionDatePlace","binding":"occasionDatePlace","box":{"x":6.25,"y":111,"width":187.5,"height":24},"visible":true,"locked":false,"style":{"fontSize":8.75,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"orderName","binding":"orderName","box":{"x":6.25,"y":151,"width":187.5,"height":32},"visible":true,"locked":false,"style":{"fontSize":12.5,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"qr","binding":"qr","box":{"x":50,"y":206.25,"width":100,"height":100},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"ticketSymbol","binding":"ticketSymbol","box":{"x":10,"y":313,"width":180,"height":20},"visible":true,"locked":false,"style":{"fontSize":8.75,"minFontSize":6,"maxLines":1,"color":"2A2A2A","align":"center"}},{"id":"footer","binding":"footer","box":{"x":6.25,"y":348,"width":187.5,"height":20},"visible":true,"locked":false,"style":{"fontSize":6.25,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}}]}}}'::jsonb)) WHERE id=(x->>'occasion')::bigint;
 INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES((x->>'occasion')::bigint,'Batch allocation','accommodation',10) RETURNING id INTO pool_id;
 INSERT INTO public.inventory_contexts(inventory_pool,title,block_date) VALUES(pool_id,'Print allocation',current_date) RETURNING id INTO context_id;
 INSERT INTO public.resources(occasion,inventory_pool,title,capacity) VALUES((x->>'occasion')::bigint,pool_id,'Fixed physical resource',10) RETURNING id INTO resource_id;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES((x->>'product')::bigint,context_id,1);
 PERFORM public.adjust_spot_capacity_for_pool(pool_id);
 PERFORM set_config('role','authenticated',true);
 r:=public.create_ticket_batch_client_sync_v1((x->>'form')::bigint,'Test batch',
  (SELECT jsonb_agg(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))) FROM generate_series(1,10)),NULL,gen_random_uuid());
 PERFORM set_config('role','none',true);
 b:=(r#>>'{data,batchId}')::uuid; oid:=(r#>>'{data,stockOrderId}')::bigint;
 PERFORM assert_not_null(b,'actual batch created through receipted command');
 r:=public.get_orders(x->>'link',NULL,NULL);
 PERFORM assert_eq(jsonb_array_length(r#>'{data,orders}'),1,'complete relational read keeps stock for Tickets');
 r:=public.get_orders_tab_data(x->>'link');
 PERFORM assert_eq(jsonb_array_length(r->'orders'),0,'ordinary order list hides stock');
 UPDATE eshop.products SET price=999 WHERE id=(x->>'product')::bigint;
 SELECT array_agg(ticket_id ORDER BY ordinal) INTO ids FROM eshop.ticket_batch_items WHERE batch_id=b;
 UPDATE eshop.tickets SET created_at=clock_timestamp()-interval '7 days' WHERE id=ANY(ids);
 SELECT jsonb_agg(jsonb_build_array(s.id,s.order_product_ticket,s.inventory_context,s.resource,s.resource_slot) ORDER BY s.id)
 INTO allocation_before FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(ids[1:3]);
 PERFORM assert_not_null(allocation_before,'batch has real allocated physical resources');
 SELECT array_agg(id ORDER BY id) INTO original_opts FROM eshop.order_product_ticket WHERE "order"=oid;
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal((x->>'form')::bigint)->>'remainingPublic')::integer,0,'stock fills form');
 r:=public.sell_ticket_batch_items_client_sync_v1(b,ids[1:3],'{}',false,gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,errorCode}','BATCH_PRINT_NOT_READY'::text,'sale before print is a terminal rejected command');
 -- SQL contract test simulates trusted resource/render completion; actual PDF bytes are covered in Edge tests.
 claim:=public.claim_ticket_batch_document(b);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.complete_ticket_batch_resources_internal(b,(claim->>'lease')::uuid,'{"test":"sealed"}',20);
 FOR part IN SELECT id,ticket_ids FROM eshop.ticket_batch_document_parts WHERE batch_id=b LOOP
  claim:=public.claim_ticket_batch_document(b,part.id);
  PERFORM public.complete_ticket_batch_document_internal(part.id,(claim->>'lease')::uuid,repeat('a',64),100,cardinality(part.ticket_ids));
 END LOOP;
 CREATE TRIGGER test_reject_batch_sale BEFORE INSERT ON eshop.orders_history FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_batch_sale();
 BEGIN
  PERFORM public.sell_ticket_batch_items_client_sync_v1(b,ids[1:3],'{}',false,cmd);
  RAISE EXCEPTION 'injected failure unexpectedly committed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'injected_after_pairing' THEN RAISE; END IF; END;
 DROP TRIGGER test_reject_batch_sale ON eshop.orders_history;
 PERFORM assert_eq((SELECT count(*) FROM public.client_mutation_receipts WHERE command_id=cmd),0::bigint,'failed sale leaves no receipt');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_product_ticket WHERE ticket=ANY(ids) AND "order"<>oid),0::bigint,'failure after pairing rolls all parents back');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions tr JOIN eshop.payment_info pi ON pi.id=tr.payment_info
 JOIN eshop.orders o ON o.payment_info=pi.id WHERE o.occasion=(x->>'occasion')::bigint),0::bigint,'failure rolls finance back');
 PERFORM set_config('role','authenticated',true);
 r:=public.sell_ticket_batch_items_client_sync_v1(b,ids[1:3],'{"email":"contact@example.invalid"}',false,cmd);
 PERFORM set_config('role','none',true);
 PERFORM assert_eq(r->>'code','200'::text,'sale at full capacity'); sold:=(r#>>'{data,orderId}')::bigint;
 PERFORM assert_not_null(sold,'sale order materialized');
 replay:=public.sell_ticket_batch_items_client_sync_v1(b,ids[1:3],'{"email":"contact@example.invalid"}',false,cmd);
 PERFORM assert_eq(replay,r,'lost response returns original receipt');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE payment_info=(SELECT payment_info FROM eshop.orders WHERE id=sold)),1::bigint,'exactly one cash fact');
 PERFORM assert_true((SELECT paid FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=sold))=300,'cash paired by existing payment owner');
 PERFORM assert_true((SELECT array_agg(id ORDER BY id) FROM eshop.order_product_ticket WHERE id=ANY(original_opts))=original_opts,'OPT identity unchanged');
 PERFORM assert_true((SELECT jsonb_agg(jsonb_build_array(s.id,s.order_product_ticket,s.inventory_context,s.resource,s.resource_slot) ORDER BY s.id)
 FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(ids[1:3]))=allocation_before,'sale preserves exact spot/OPT/context/resource/slot identities');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=sold),0::bigint,'contact without opt-in creates no delivery');
 r:=public.void_ticket_batch_items_client_sync_v1(b,ids[4:5],'Unused print',gen_random_uuid());
 r:=public.get_ticket_batch_detail(b);
 PERFORM assert_eq((r#>>'{counts,available}')::integer,5,'five available');
 PERFORM assert_true((r->>'stockValue')::numeric=500,'remaining stock value uses immutable prices');
 PERFORM assert_true((r->>'receivedAmount')::numeric=300,'received money uses existing financial facts');
 PERFORM assert_eq((r#>>'{counts,soldActive}')::integer,3,'three sold active');
 PERFORM assert_eq((r#>>'{counts,voidedUnsold}')::integer,2,'two unsold void');
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal((x->>'form')::bigint)->>'occupiedPeople')::integer,8,'only void frees capacity');
 PERFORM assert_true(NOT has_table_privilege('authenticated','eshop.ticket_batch_items','UPDATE'),'no direct item writes');
 UPDATE public.unit_users SET is_manager=false WHERE unit=(x->>'unit')::bigint AND "user"=(x->>'actor')::uuid;
 BEGIN
  PERFORM public.sell_ticket_batch_items_client_sync_v1(b,ids[1:3],'{"email":"contact@example.invalid"}',false,cmd);
  RAISE EXCEPTION 'revoked manager replay disclosed receipt';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE public.unit_users SET is_manager=true WHERE unit=(x->>'unit')::bigint AND "user"=(x->>'actor')::uuid;
  r:=public.sell_ticket_batch_items_client_sync_v1(b,ids[6:6],'{"email":"optin@example.invalid"}',true,email_cmd);
  PERFORM assert_eq(r->>'code','200'::text,'explicit opt-in cash sale succeeds');
  email_order:=(r#>>'{data,orderId}')::bigint;
  PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=email_order AND message_kind='order_tickets'),1::bigint,'opt-in queues through the single global email domain');
  replay:=public.sell_ticket_batch_items_client_sync_v1(b,ids[6:6],'{"email":"optin@example.invalid"}',true,email_cmd);
  PERFORM assert_eq(r,replay,'email sale retry replays one receipt');
  PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=email_order),1::bigint,'one delivery intent after replay');
  RAISE EXCEPTION 'rollback_email_fixture';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'rollback_email_fixture' THEN RAISE; END IF; END;
 BEGIN
  UPDATE public.unit_users SET is_manager=true WHERE unit=(x->>'unit')::bigint AND "user"=(x->>'actor')::uuid;
  INSERT INTO eshop.external_services(unit,type,data) VALUES((x->>'unit')::bigint,'FAKTUROID','{}');
  BEGIN
   PERFORM public.preview_ticket_batch((x->>'form')::bigint,jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))));
   RAISE EXCEPTION 'invoice preview accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CASH_SALE_INVOICE_WORKFLOW_REQUIRED' THEN RAISE; END IF; END;
  r:=public.create_ticket_batch_client_sync_v1((x->>'form')::bigint,'Incompatible invoice batch',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))),NULL,gen_random_uuid());
  PERFORM assert_eq(r#>>'{data,errorCode}','CASH_SALE_INVOICE_WORKFLOW_REQUIRED'::text,'invoice create is rejected without new stock');
  r:=public.sell_ticket_batch_items_client_sync_v1(b,ids[6:6],'{}',false,gen_random_uuid());
  PERFORM assert_eq(r#>>'{data,errorCode}','CASH_SALE_INVOICE_WORKFLOW_REQUIRED'::text,'later invoice activation blocks sale');
  r:=public.void_ticket_batch_items_client_sync_v1(b,ids[6:6],'Release incompatible stock',gen_random_uuid());
  PERFORM assert_eq(r->>'code','200'::text,'invoice activation does not block releasing unsold stock');
  RAISE EXCEPTION 'rollback_invoice_fixture';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'rollback_invoice_fixture' THEN RAISE; END IF; END;
 report:=public.get_report_ws(x->>'link');
 PERFORM assert_eq((report#>>'{report,orders,total}')::integer,1,'report excludes technical stock');
 PERFORM assert_eq(report#>>'{report,timeline,tickets,0,day}',(SELECT (created_at AT TIME ZONE 'Europe/Prague')::date::text FROM eshop.orders WHERE id=sold),'sales timeline uses sale date, not earlier print date');
END $$;
ROLLBACK;
