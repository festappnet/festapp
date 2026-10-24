-- Private until immutable documents and the complete UI are available.
CREATE OR REPLACE FUNCTION public.create_ticket_batch_client_sync_v1(
 p_form bigint,p_title text,p_selection jsonb,p_secret uuid,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; o public.occasions; claimed jsonb; selection jsonb; oid bigint; tid bigint; symbol text;
 item jsonb; products jsonb; tickets jsonb:='[]'; currency text; result jsonb; bid uuid; ordinal integer:=0; snap jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 IF auth.uid() IS NULL OR public.get_is_editor_order_on_occasion(f.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 IF length(trim(p_title)) NOT BETWEEN 1 AND 200 OR p_title IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='BATCH_TITLE_INVALID'; END IF;
 selection:=public.normalize_ticket_batch_selection_internal(f.id,p_selection);
 claimed:=public.begin_client_mutation_v1(p_command_id,'inventory.ticket_batch.create',f.occasion,auth.uid(),
  encode(extensions.digest(jsonb_build_object('form',f.id,'title',p_title,'selection',selection,'secret',p_secret)::text,'sha256'),'hex'));
 IF claimed->>'disposition'='replay' THEN RETURN claimed->'response'; END IF;
 BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=f.occasion;
 PERFORM public.check_ticket_batch_eligible_internal(f.id);
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('batch-create',o.unit,o.organization),
 jsonb_build_object('actor',auth.uid(),'unit',o.unit,'organization',o.organization),jsonb_build_object('batch-create.items',jsonb_array_length(selection)));
 IF f.participant_capacity IS NOT NULL AND jsonb_array_length(selection)>(public.get_form_capacity_snapshot_internal(f.id)->>'remainingPublic')::bigint THEN
  RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
 oid:=public.allocate_ticket_order_identity_internal(f.id);
 PERFORM public.lock_ticket_order_products_internal(oid,jsonb_build_object('ticket',selection));
 PERFORM public.ticket_batch_selection_summary_internal(f.id,selection);
 PERFORM public.hold_ticket_batch_spots_internal(f.id,ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(selection) t WHERE t->>'spot' IS NOT NULL ORDER BY (t->>'spot')::bigint),p_secret);
 FOR item IN SELECT value FROM jsonb_array_elements(selection) LOOP
  IF item->>'spot' IS NOT NULL THEN
   PERFORM 1 FROM eshop.spots WHERE id=(item->>'spot')::bigint AND blueprint=f.blueprint AND occasion=f.occasion
    AND secret=p_secret AND secret_expiration_time>clock_timestamp() AND order_product_ticket IS NULL FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_SPOT_HOLD_REQUIRED'; END IF;
  END IF;
  symbol:=public.generate_ticket_symbol(o.organization,o.id);
  INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(o.id,'ordered',symbol) RETURNING id INTO tid;
  products:=public.materialize_ticket_products_internal_v1(oid,f.id,tid,item,p_secret);
  IF currency IS NULL THEN currency:=products->>'currency_code';
  ELSIF currency IS DISTINCT FROM products->>'currency_code' THEN RAISE EXCEPTION 'BATCH_CURRENCY_MISMATCH'; END IF;
  tickets:=tickets||jsonb_build_object('id',tid,'ticket_symbol',symbol,'products',products->'products');
 END LOOP;
 PERFORM public.apply_allocations(oid);
 tickets:=public.order_tickets_with_seating_internal(oid,tickets);
 UPDATE eshop.orders SET state='stock',price=NULL,payment_info=NULL,currency_code=currency,data=jsonb_build_object('tickets',tickets),updated_at=clock_timestamp() WHERE id=oid;
 SELECT jsonb_build_object('occasion',to_jsonb(o),'catalog',public.get_products_and_types(o.id)::jsonb,
 'tickets',tickets,'documentData',(SELECT jsonb_agg(jsonb_set(d,'{ticket,price_decimal_digits}',to_jsonb(CASE WHEN (d#>>'{ticket,price}')::numeric=trunc((d#>>'{ticket,price}')::numeric) THEN 0 ELSE 2 END),true) ORDER BY (x->>'id')::bigint)
 FROM jsonb_array_elements(tickets) x CROSS JOIN LATERAL (SELECT public.get_ticket_details_for_generating((x->>'id')::bigint) d) frozen),'renderContractVersion',1) INTO snap;
 INSERT INTO eshop.ticket_batches(occasion,form,stock_order_id,title,created_by,currency_code,snapshot)
 VALUES(o.id,f.id,oid,trim(p_title),auth.uid(),currency,snap) RETURNING id INTO bid;
 INSERT INTO eshop.ticket_batch_items(batch_id,ticket_id,ordinal)
 SELECT bid,(value->>'id')::bigint,n FROM jsonb_array_elements(tickets) WITH ORDINALITY x(value,n);
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=f.id;
 INSERT INTO eshop.orders_history("order",state,data,currency_code) VALUES(oid,'stock',jsonb_build_object('batchId',bid),currency);
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.id,'inventory.ticket_batch.create',
 jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','insert','safeLabel','Ticket batch',
 'changedFields',jsonb_build_array('tickets','allocations'))),ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=o.id AND is_editor_order_view),
 jsonb_build_object('batchId',bid,'stockOrderId',oid,'count',jsonb_array_length(selection)));
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM=ANY(ARRAY['FORM_CAPACITY_EXCEEDED','PRODUCT_CAPACITY_EXCEEDED','BATCH_SPOT_UNAVAILABLE','BATCH_SPOT_HOLD_REQUIRED','BATCH_CURRENCY_MISMATCH','BATCH_PRODUCT_UNAVAILABLE','BATCH_ADMISSION_PRODUCT_REQUIRED','CASH_SALE_INVOICE_WORKFLOW_REQUIRED','BATCH_ANONYMOUS_TEMPLATE_REQUIRED','BATCH_PERSONAL_REGISTRATION_UNSUPPORTED']) THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('errorCode',SQLERRM));
  END IF;
  RAISE;
 END;
END $$;
REVOKE ALL ON FUNCTION public.create_ticket_batch_client_sync_v1(bigint,text,jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
