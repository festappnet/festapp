-- A sale moves existing OPT parents. It never allocates inventory or generates QR.
CREATE OR REPLACE FUNCTION public.sell_ticket_batch_items_client_sync_v1(
 p_batch uuid,p_tickets bigint[],p_contact jsonb,p_send_tickets boolean,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; occ public.occasions; claimed jsonb; oid bigint; pi bigint; tx bigint;
 v_amount numeric; tickets jsonb; sale_data jsonb; ids bigint[]; email text;
BEGIN
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=b.occasion;
 IF auth.uid() IS NULL OR public.can_write_orders(b.occasion) IS NOT TRUE
 OR public.get_is_manager_on_unit(occ.unit) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id ORDER BY id);
 IF cardinality(ids) NOT BETWEEN 1 AND 20 OR array_position(ids,NULL) IS NOT NULL
 OR cardinality(ids) IS NULL OR p_send_tickets IS NULL
 OR jsonb_typeof(coalesce(p_contact,'{}'))<>'object' OR octet_length(coalesce(p_contact,'{}')::text)>8192
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(coalesce(p_contact,'{}')) k WHERE k NOT IN ('email','name','surname','phone')) THEN
  RAISE invalid_parameter_value USING MESSAGE='BATCH_SALE_SELECTION_INVALID'; END IF;
 sale_data:=jsonb_strip_nulls(coalesce(p_contact,'{}'));
 email:=nullif(trim(sale_data->>'email'),'');
 IF email IS NULL THEN sale_data:=sale_data-'email';
 ELSIF NOT public.email_address_is_valid(email) THEN RAISE EXCEPTION 'BATCH_CONTACT_INVALID';
 ELSE sale_data:=jsonb_set(sale_data,'{email}',to_jsonb(email)); END IF;
 IF p_send_tickets AND email IS NULL THEN RAISE EXCEPTION 'BATCH_DELIVERY_EMAIL_REQUIRED'; END IF;
 claimed:=public.begin_client_mutation_v1(p_command_id,'inventory.ticket_batch.sell',b.occasion,auth.uid(),
 encode(extensions.digest(jsonb_build_object('batch',b.id,'tickets',ids,'contact',sale_data,'sendTickets',p_send_tickets)::text,'sha256'),'hex'));
 IF claimed->>'disposition'='replay' THEN RETURN claimed->'response'; END IF;
 BEGIN
 PERFORM public.check_ticket_batch_cash_unit_internal(b.occasion);
 PERFORM public.admit_order_mutation_v1(b.occasion,cardinality(ids));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[b.stock_order_id]);
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch FOR UPDATE;
 IF b.manifest_hash IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND kind='print')
 OR EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND state<>'ready') THEN
  RAISE EXCEPTION 'BATCH_PRINT_NOT_READY'; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 IF (SELECT count(*) FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id
  WHERE i.batch_id=b.id AND t.id=ANY(ids) AND i.sale_order_id IS NULL AND t.state='ordered'
  AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=b.stock_order_id)
  AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"<>b.stock_order_id))<>cardinality(ids) THEN
  RAISE EXCEPTION 'ITEM_NOT_IN_STOCK'; END IF;
 SELECT jsonb_agg(t ORDER BY (t->>'id')::bigint) INTO tickets FROM jsonb_array_elements(b.snapshot->'tickets') t WHERE (t->>'id')::bigint=ANY(ids);
 SELECT sum((p->>'price')::numeric) INTO v_amount FROM jsonb_array_elements(tickets) t CROSS JOIN LATERAL jsonb_array_elements(t->'products') p;
 IF v_amount IS NULL OR v_amount<0 THEN RAISE EXCEPTION 'BATCH_SNAPSHOT_INVALID'; END IF;
 oid:=public.allocate_ticket_order_identity_internal(b.form);
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method) VALUES(v_amount,b.currency_code,'bank') RETURNING id INTO pi;
 sale_data:=sale_data||jsonb_build_object('tickets',tickets,'ticketBatchOrigin',jsonb_build_object('batchId',b.id,'sendTickets',p_send_tickets));
 UPDATE eshop.orders SET price=v_amount,currency_code=b.currency_code,payment_info=pi,data=sale_data,updated_at=clock_timestamp() WHERE id=oid;
 UPDATE eshop.order_product_ticket SET "order"=oid WHERE ticket=ANY(ids) AND "order"=b.stock_order_id;
 UPDATE eshop.ticket_batch_items SET sale_order_id=oid WHERE batch_id=b.id AND ticket_id=ANY(ids) AND sale_order_id IS NULL;
 UPDATE eshop.orders stock SET data=jsonb_set(stock.data,'{tickets}',coalesce((SELECT jsonb_agg(t) FROM jsonb_array_elements(stock.data->'tickets') t
  WHERE NOT (t->>'id')::bigint=ANY(ids)),'[]')),updated_at=clock_timestamp() WHERE id=b.stock_order_id;
 tx:=public.insert_manual_transaction_internal_v1(v_amount,b.currency_code,occ.unit,NULL,clock_timestamp(),'Ticket batch cash sale',pi);
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND state='paid')
 OR NOT EXISTS(SELECT 1 FROM eshop.transactions tr WHERE tr.id=tx AND tr.payment_info=pi AND tr.amount=v_amount) THEN
  RAISE EXCEPTION 'BATCH_PAYMENT_NOT_COMMITTED'; END IF;
 INSERT INTO eshop.orders_history("order",state,data,price,currency_code) VALUES
 (b.stock_order_id,'stock',jsonb_build_object('saleOrderId',oid,'ticketIds',ids),NULL,b.currency_code),
 (oid,'paid',jsonb_build_object('batchId',b.id,'transactionId',tx,'ticketIds',ids),v_amount,b.currency_code);
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=b.form;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,b.occasion,'inventory.ticket_batch.sell',
 jsonb_build_array(jsonb_build_object('entityType','order','entityId',b.stock_order_id,'operation','update','safeLabel','Ticket batch',
 'changedFields',jsonb_build_array('tickets','parent')),jsonb_build_object('entityType','order','entityId',oid,'operation','insert',
 'safeLabel','Cash sale','changedFields',jsonb_build_array('tickets','payment','parent'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=b.occasion AND is_editor_order_view),
 jsonb_build_object('batchId',b.id,'orderId',oid,'transactionId',tx,'amount',v_amount,'currency',b.currency_code,'ticketIds',ids));
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM=ANY(ARRAY['ITEM_NOT_IN_STOCK','BATCH_PRINT_NOT_READY','CASH_SALE_INVOICE_WORKFLOW_REQUIRED']) THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('errorCode',SQLERRM));
  END IF;
  RAISE;
 END;
END $$;
CREATE OR REPLACE FUNCTION public.void_ticket_batch_items_client_sync_v1(p_batch uuid,p_tickets bigint[],p_reason text,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; ids bigint[]; claimed jsonb;
BEGIN
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch;
 IF auth.uid() IS NULL OR public.can_write_orders(b.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id ORDER BY id);
 IF cardinality(ids) NOT BETWEEN 1 AND 200 OR cardinality(ids) IS NULL OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 OR p_reason IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='BATCH_VOID_SELECTION_INVALID'; END IF;
 claimed:=public.begin_client_mutation_v1(p_command_id,'inventory.ticket_batch.void',b.occasion,auth.uid(),
 encode(extensions.digest(jsonb_build_object('batch',b.id,'tickets',ids,'reason',p_reason)::text,'sha256'),'hex'));
 IF claimed->>'disposition'='replay' THEN RETURN claimed->'response'; END IF;
 BEGIN
 PERFORM public.admit_order_mutation_v1(b.occasion,cardinality(ids));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[b.stock_order_id]);
 PERFORM 1 FROM eshop.ticket_batches WHERE id=b.id FOR UPDATE;
 PERFORM 1 FROM eshop.tickets WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 IF (SELECT count(*) FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id
  WHERE i.batch_id=b.id AND t.id=ANY(ids) AND i.sale_order_id IS NULL AND t.state='ordered'
  AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=b.stock_order_id))<>cardinality(ids) THEN
  RAISE EXCEPTION 'ITEM_NOT_IN_STOCK'; END IF;
 PERFORM public.internal_storno_tickets_221(ids);
 INSERT INTO eshop.orders_history("order",state,data,currency_code)
 VALUES(b.stock_order_id,'stock',jsonb_build_object('voidedTicketIds',ids,'reason',p_reason),b.currency_code);
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,b.occasion,'inventory.ticket_batch.void',
 jsonb_build_array(jsonb_build_object('entityType','order','entityId',b.stock_order_id,'operation','update','safeLabel','Ticket batch',
 'changedFields',jsonb_build_array('tickets','allocations'))),ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=b.occasion AND is_editor_order_view),
 jsonb_build_object('batchId',b.id,'ticketIds',ids));
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='ITEM_NOT_IN_STOCK' THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('errorCode',SQLERRM));
  END IF;
  RAISE;
 END;
END $$;
REVOKE ALL ON FUNCTION public.sell_ticket_batch_items_client_sync_v1(uuid,bigint[],jsonb,boolean,uuid),
 public.void_ticket_batch_items_client_sync_v1(uuid,bigint[],text,uuid) FROM PUBLIC,anon,authenticated,service_role;
