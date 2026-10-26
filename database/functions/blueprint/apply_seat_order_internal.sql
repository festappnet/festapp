-- Actual cancellation + creation, shared by rollback quote and the one receipt.
-- Commercial calculation remains in the existing cancellation/finalize owners.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_order_internal(p_spots bigint[],p_input jsonb,p_command uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];affected bigint[];seats jsonb;occ bigint;form_id bigint;analysis jsonb;details jsonb;normalized jsonb;products bigint[];
 old_orders bigint[];before_orders jsonb;before_facts jsonb;form_facts jsonb;prepared jsonb;created jsonb;
 effects jsonb;new_order eshop.orders;new_products jsonb;semantic jsonb;revision jsonb;
BEGIN
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(p_spots) id WHERE id IS NOT NULL ORDER BY id);
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id=ANY(ids);
 IF occ IS NULL OR cardinality(ids)=0 OR cardinality(ids)>20000 OR
  (SELECT count(*) FROM eshop.spots WHERE id=ANY(ids) AND occasion=occ)<>cardinality(ids)
  OR public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 affected:=public.blueprint_order_affected_spots_internal(ids);
 PERFORM public.check_blueprint_swap_scope_internal(occ,affected);
 analysis:=public.analyze_new_order_spots(ids);
 details:=public.blueprint_order_input_internal(ids,p_input,analysis);
 SELECT id INTO form_id FROM public.forms WHERE key=(details->>'form')::uuid;
 -- Lock destination and existing forms together, before any order/product child.
 PERFORM 1 FROM public.forms WHERE id IN(SELECT form_id UNION SELECT o.form
  FROM eshop.orders o JOIN eshop.order_product_ticket i ON i."order"=o.id
  JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(ids)) ORDER BY id FOR UPDATE;
 analysis:=public.analyze_new_order_spots(ids);
 IF analysis#>>'{order_form,key}' IS DISTINCT FROM details->>'form' THEN
  RAISE serialization_failure USING MESSAGE='order form changed; retry the same command'; END IF;
 normalized:=public.normalize_form_ticket_answers_internal(form_id,details->'ticket');
 SELECT ARRAY(SELECT DISTINCT (f->>'product_type')::bigint FROM jsonb_array_elements(normalized) t
  CROSS JOIN LATERAL jsonb_array_elements(t->'fields') f WHERE f->>'product_type' IS NOT NULL ORDER BY 1) INTO products;
 IF EXISTS(SELECT 1 FROM unnest(products) requested(id) LEFT JOIN eshop.products p ON p.id=requested.id
  LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.id IS NULL OR pt.occasion IS DISTINCT FROM occ) THEN
  RAISE insufficient_privilege USING MESSAGE='order product scope unavailable'; END IF;
 PERFORM public.lock_spot_assignment_scope_internal(affected,'{}'::bigint[],true,products);
 IF affected IS DISTINCT FROM public.blueprint_order_affected_spots_internal(ids) THEN
  RAISE serialization_failure USING MESSAGE='order seat parents changed; retry the same command'; END IF;
 PERFORM public.check_blueprint_swap_scope_internal(occ,affected);
 IF EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
  WHERE p.id=ANY(products) AND pt.occasion IS DISTINCT FROM occ) THEN
  RAISE insufficient_privilege USING MESSAGE='order product scope unavailable'; END IF;
 PERFORM public.check_blueprint_selection_units_internal(ids);
 SELECT array_agg(DISTINCT i."order") INTO old_orders FROM eshop.spots s
 JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket WHERE s.id=ANY(ids);
 before_orders:=public.order_payment_snapshot_internal(old_orders);
 -- Customer facts and all required form definitions bind consent privately;
 -- the scoped MCP projection never receives existing customer identities.
 analysis:=public.analyze_new_order_spots(ids);
 SELECT to_jsonb(f)-'updated_at'-'created_at' INTO form_facts FROM public.forms f WHERE id=form_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'revision',b.layout_revision) ORDER BY b.id),'[]')
 INTO revision FROM eshop.blueprints b WHERE b.id IN(SELECT blueprint FROM eshop.spots WHERE id=ANY(affected));
 WITH lifecycle AS MATERIALIZED (SELECT * FROM public.blueprint_spot_facts_internal(occ,affected))
 SELECT coalesce(jsonb_object_agg(s.id::text,jsonb_build_object('spot',s.id,'product',s.product,'price',p.price,'currency',p.currency_code,
  'item',s.order_product_ticket,'ticketState',t.state,'hold',s.secret,'expires',extract(epoch FROM s.secret_expiration_time),'state',lifecycle.state,'ticket',i.ticket,'order',i."order")),'{}')
 INTO before_facts FROM eshop.spots s LEFT JOIN eshop.products p ON p.id=s.product
 LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket LEFT JOIN eshop.tickets t ON t.id=i.ticket LEFT JOIN lifecycle ON lifecycle.id=s.id WHERE s.id=ANY(affected);
 prepared:=public.confirm_blueprint_order_change_internal_v1(ids,p_input);
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF coalesce((prepared->>'success')::boolean,false) IS NOT TRUE THEN
  RAISE check_violation USING MESSAGE='replacement preparation rejected',DETAIL=prepared::text; END IF;
 created:=public.create_ticket_order_internal_v1(prepared->'orderDetails');
 IF coalesce((created->>'code')::integer,500)<>200 THEN
  RAISE check_violation USING MESSAGE='replacement order rejected',DETAIL=created::text; END IF;
 PERFORM public.enqueue_ticket_order_confirmation_v1(p_command,occ,created,coalesce(p_input->>'lang',prepared#>>'{orderDetails,lang}'));
 SELECT * INTO new_order FROM eshop.orders WHERE id=(created#>>'{order,id}')::bigint;
 IF created#>>'{order,payment_info,payment_method}'='stripe' THEN
  RAISE check_violation USING MESSAGE='STRIPE_REPLACEMENT_UNSUPPORTED'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',id,'beforeAmount',(before_orders->id::text->>'amount')::numeric,
  'afterAmount',price,'delta',price-(before_orders->id::text->>'amount')::numeric,'currencyCode',currency_code,
  'beforeState',before_orders->id::text->>'state','afterState',state) ORDER BY id),'[]')
 INTO effects FROM eshop.orders WHERE id=ANY(old_orders);
 WITH ticket_spots AS MATERIALIZED (SELECT s.id,i.ticket FROM eshop.spots s
  JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket WHERE s.id=ANY(ids))
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'productId',(p->>'id')::bigint,'title',p->'title',
  'amount',p->>'price','currencyCode',p->'currency_code') ORDER BY s.id,(p->>'id')::bigint,(p->>'price')::numeric),'[]')
 INTO new_products FROM jsonb_array_elements(new_order.data->'tickets') t
 JOIN ticket_spots s ON s.ticket=(t->>'id')::bigint CROSS JOIN LATERAL jsonb_array_elements(t->'products') p;
 WITH lifecycle AS MATERIALIZED (SELECT * FROM public.blueprint_spot_facts_internal(occ,affected))
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'blueprintId',s.blueprint,'blueprintTitle',b.title,'title',s.title,
  'stateBefore',before_facts->s.id::text->'state','stateAfter',f.state,
  'previousOrderId',before_facts->s.id::text->'order','previousTicketId',before_facts->s.id::text->'ticket',
  'productId',s.product,'productTitle',p.title) ORDER BY s.id),'[]')
 INTO seats FROM eshop.spots s LEFT JOIN eshop.products p ON p.id=s.product LEFT JOIN eshop.blueprints b ON b.id=s.blueprint LEFT JOIN lifecycle f ON f.id=s.id WHERE s.id=ANY(affected);
 semantic:=jsonb_build_object('spotIds',ids,'affectedSpotIds',affected,
  'releasedSpotIds',ARRAY(SELECT id FROM unnest(affected) id WHERE NOT id=ANY(ids)),
  'seats',seats,'blueprints',revision,'formKey',details->'form','orders',effects,
  'newOrder',jsonb_build_object('amount',new_order.price::text,'currencyCode',new_order.currency_code,
   'state',new_order.state,'paymentMethod',created#>'{order,payment_info,payment_method}',
   'ticketCount',(SELECT count(DISTINCT ticket) FROM eshop.order_product_ticket WHERE "order"=new_order.id),
   'products',new_products));
 PERFORM public.check_occasion_writable(occ);
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 RETURN jsonb_build_object('result',created,'quote',semantic,'analysis',analysis,
  'confirmationHash',encode(extensions.digest(convert_to(jsonb_build_object('actor',auth.uid(),'quote',semantic,
   'input',p_input,'beforeOrders',before_orders,'facts',before_facts,'analysis',analysis,'form',form_facts,
   'paymentRecipient',jsonb_build_object('account',created#>'{order,payment_info,account_number}',
    'accountLabel',created#>'{order,payment_info,account_number_human_readable}',
    'creditor',created#>'{order,payment_info,creditor_name}','deposit',created#>'{order,payment_info,deposit_amount}'),
   'effectiveForm',created#>'{order,form,data}','occasionFeatures',created#>'{order,occasion,features}')::text,'UTF8'),'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_order_internal(bigint[],jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
