-- Selection validation is shared with the ordinary product materializer.

CREATE OR REPLACE FUNCTION public.remap_customer_move_answers_internal(p_data jsonb,p_source bigint,p_target bigint,p_map jsonb,p_ticket boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb:='[]'; field public.form_fields; source_field public.form_fields; source_id text; val jsonb;
BEGIN
 FOR field IN SELECT * FROM public.form_fields WHERE form=p_target AND coalesce(is_ticket_field,false)=p_ticket
  AND NOT coalesce(is_hidden,false) AND type NOT IN ('ticket','product_type') LOOP
  SELECT key INTO source_id FROM jsonb_each_text(coalesce(p_map,'{}')) WHERE value=field.id::text;
  SELECT * INTO source_field FROM public.form_fields WHERE form=p_source AND id::text=source_id AND type=field.type
   AND coalesce(is_ticket_field,false)=p_ticket AND NOT coalesce(is_hidden,false);
  SELECT v->source_id INTO val FROM jsonb_array_elements(coalesce(p_data->'fields','[]')) v WHERE v ? source_id LIMIT 1;
  IF source_field.id IS NULL OR field.type NOT IN ('name','surname','phone','email','text','city','address','select_one') THEN val:=NULL; END IF;
  IF field.is_required AND (val IS NULL OR jsonb_typeof(val)<>'string' OR nullif(btrim(val#>>'{}'),'') IS NULL) THEN
   RAISE EXCEPTION 'TARGET_ANSWERS_REQUIRED'; END IF;
  IF val IS NOT NULL THEN
   IF field.type='select_one' AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(field.data->'options','[]')) option WHERE option->'value'=val) THEN
    RAISE EXCEPTION 'TARGET_ANSWERS_INVALID'; END IF;
   result:=result||jsonb_build_array(jsonb_build_object(field.id::text,val));
  END IF;
 END LOOP;
 RETURN jsonb_set(coalesce(p_data,'{}'),'{fields}',result);
END $$;
REVOKE ALL ON FUNCTION public.remap_customer_move_answers_internal(jsonb,bigint,bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_move_preview_internal(p_order bigint,p_target bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; src public.forms; dst public.forms; cfg jsonb; mapping jsonb; field_map jsonb; capacity jsonb;
 item record; product eshop.products; ticket eshop.tickets; ids bigint[]; n bigint; reason text; order_data jsonb;
 items jsonb:='[]'; tickets jsonb:='[]'; td jsonb; snapshot jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT src FROM public.forms WHERE id=o.form;
 SELECT * INTO dst FROM public.forms WHERE id=p_target;
 SELECT v INTO cfg FROM jsonb_array_elements(coalesce(public.customer_order_policy_internal(src.id)#>'{policy,move,targets}','[]')) v
 WHERE v->>'formId'=p_target::text;
 IF dst.id IS NULL OR dst.id=src.id OR cfg IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_MOVE_TARGET_UNAVAILABLE'; END IF;
 mapping:=coalesce(cfg->'products','{}');field_map:=coalesce(cfg->'fields','{}');
 capacity:=public.get_form_capacity_snapshot_internal(dst.id);
 SELECT count(*) INTO n FROM public.get_order_tickets_internal(o.id);
 reason:=CASE WHEN dst.occasion<>src.occasion THEN 'different_occasion'
  WHEN dst.term_start_at IS NULL OR src.term_start_at IS NULL OR dst.term_end_at IS NULL OR src.term_end_at IS NULL THEN 'term_unavailable'
  WHEN NOT public.customer_order_operation_enabled_internal(dst.id,'move') THEN 'target_policy_unavailable'
  WHEN NOT coalesce((public.get_form_availability_snapshot_internal(dst.id)->>'isWindowOpen')::boolean,false) THEN 'target_closed'
  WHEN src.blueprint IS NOT NULL OR dst.blueprint IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE x."order"=o.id) THEN 'seating_requires_review'
  WHEN (capacity->>'remainingPublic')::bigint<n THEN 'target_full' END;
 BEGIN
  PERFORM public.assert_order_discount_unchanged_internal(o.id);
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='DISCOUNTED_ORDER_PRICE_IMMUTABLE' THEN reason:='discount_requires_review'; ELSE RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info AND
   (pi.deposit_amount IS NOT NULL OR (pi.payment_method='bank' AND dst.bank_account IS DISTINCT FROM pi.bank_account))) THEN reason:='payment_scope_requires_review'; END IF;
 IF public.payment_method_context_internal(o.id)->'invalidIdentity' IS DISTINCT FROM 'false'::jsonb
  OR coalesce((public.payment_method_context_internal(o.id)->>'pending')::numeric,0)>0
  OR public.provider_order_payment_projection_internal(o.id)->'reconciliationPending'='true'::jsonb
  OR public.provider_order_payment_projection_internal(o.id)->>'status' IN ('disputed','unknown','action_required') THEN reason:='finance_requires_review'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info AND public.payment_method_is_online_internal(pi.payment_method)
   AND (o.state NOT IN ('paid','sent') OR (public.get_effective_form_data(dst.id)#>ARRAY['payments','providerConnections',pi.payment_method]) IS DISTINCT FROM (to_jsonb(pi)->(pi.payment_method||'_connection_id')))) THEN reason:='payment_scope_requires_review'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.product_inventory_contexts c ON c.product=x.product WHERE x."order"=o.id) THEN reason:='inventory_requires_review'; END IF;
 BEGIN
  order_data:=public.remap_customer_move_answers_internal(o.data,src.id,dst.id,field_map,false);
  FOR ticket IN SELECT * FROM public.get_order_tickets_internal(o.id) LOOP
   ids:='{}'; items:='[]';
   FOR item IN SELECT * FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=ticket.id LOOP
    SELECT * INTO product FROM eshop.products WHERE id::text=mapping->>item.product::text;
    IF product.id IS NULL OR product.occasion<>src.occasion OR product.is_hidden
     OR product.currency_code<>o.currency_code OR product.price IS DISTINCT FROM item.net_price
     OR NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=dst.id AND product_type=product.product_type AND NOT is_hidden)
     OR EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product=product.id) THEN
      RAISE EXCEPTION 'PRODUCT_MAPPING_UNAVAILABLE'; END IF;
    IF product.maximum>0 AND (SELECT count(*) FROM eshop.order_product_ticket existing WHERE existing.product=product.id AND existing."order"<>o.id)
      +(SELECT count(*) FROM eshop.order_product_ticket x WHERE x."order"=o.id AND mapping->>x.product::text=product.id::text)>product.maximum THEN
      RAISE EXCEPTION 'TARGET_PRODUCT_FULL'; END IF;
    ids:=array_append(ids,product.id);
    items:=items||jsonb_build_array(jsonb_build_object('id',product.id,'title',product.title,'price',product.price,'currency_code',product.currency_code));
   END LOOP;
   IF cardinality(ids)<>(SELECT count(DISTINCT id) FROM unnest(ids) id) THEN RAISE EXCEPTION 'PRODUCT_MAPPING_AMBIGUOUS'; END IF;
   PERFORM public.assert_ticket_required_products_internal(dst.id,ids);
   td:=public.remap_customer_move_answers_internal(ticket.data,src.id,dst.id,field_map,true);
   tickets:=tickets||jsonb_build_array(jsonb_build_object('id',ticket.id,'fields',td->'fields','products',items));
  END LOOP;
 EXCEPTION WHEN raise_exception THEN reason:=coalesce(reason,'target_configuration_requires_review'); END;
 RETURN jsonb_build_object('formId',dst.id,'title',dst.title,'startsAt',dst.term_start_at,'endsAt',dst.term_end_at,
  'automatic',reason IS NULL,'reason',reason,'capacity',capacity-'serverTime','priceDifference',0,'tickets',tickets,
  'orderFields',order_data->'fields','products',mapping,'fieldMap',field_map);
END $$;
REVOKE ALL ON FUNCTION public.customer_move_preview_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_move_targets_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(public.customer_move_preview_internal(o.id,(t->>'formId')::bigint)),'[]')
 FROM eshop.orders o CROSS JOIN LATERAL jsonb_array_elements(coalesce(public.customer_order_policy_internal(o.form)#>'{policy,move,targets}','[]')) t
 WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.customer_move_targets_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.move_customer_order_domain_internal(p_order bigint,p_target bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; preview jsonb; ticket jsonb; symbol text; ticket_snapshots jsonb; source bigint; org bigint;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;source:=o.form;
 PERFORM public.assert_order_discount_unchanged_internal(o.id);
 preview:=public.customer_move_preview_internal(o.id,p_target);
 IF preview->'automatic' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=o.occasion;
 -- Retain an explicit original snapshot; no price/payment mutation is allowed.
 INSERT INTO eshop.orders_history("order",state,price,data,currency_code) VALUES(o.id,o.state,o.price,o.data||jsonb_build_object('formId',source),o.currency_code);
 UPDATE eshop.order_product_ticket x SET product=(preview#>>ARRAY['products',x.product::text])::bigint
 WHERE x."order"=o.id;
 FOR ticket IN SELECT value FROM jsonb_array_elements(preview->'tickets') LOOP
  symbol:=public.generate_ticket_symbol(org,o.occasion);
  UPDATE eshop.tickets t SET ticket_symbol=symbol,data=jsonb_set(coalesce(t.data,'{}'),'{fields}',ticket->'fields') WHERE id=(ticket->>'id')::bigint;
  ticket:=ticket||jsonb_build_object('ticket_symbol',symbol);
  ticket_snapshots:=coalesce(ticket_snapshots,'[]')||jsonb_build_array(ticket);
 END LOOP;
 UPDATE eshop.orders SET form=p_target,data=jsonb_set(jsonb_set(o.data,'{fields}',preview->'orderFields'),'{tickets}',coalesce(ticket_snapshots,'[]')),
  email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
 -- The established overview URL and token continue to follow this same order.
 UPDATE eshop.waitlist_capabilities SET form_id=p_target WHERE order_id=o.id AND kind='order_view' AND revoked_at IS NULL;
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(source,p_target);
 PERFORM public.cancel_order_email_intents(o.id);
 PERFORM public.refresh_order_wallet_term_domain_internal(o.id);
 PERFORM public.enqueue_order_wallet_internal(o.id);
 IF o.state IN ('paid','sent') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
 INSERT INTO eshop.orders_history("order",state,price,data,currency_code)
 SELECT ord.id,ord.state,ord.price,ord.data||jsonb_build_object('formId',ord.form),ord.currency_code FROM eshop.orders ord WHERE ord.id=o.id;
END $$;
REVOKE ALL ON FUNCTION public.move_customer_order_domain_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
