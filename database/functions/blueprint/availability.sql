-- Same counts and context quantities as finalize_ticket_order/apply_allocations.
-- This snapshot never reserves quantity; checkout remains authoritative.
CREATE OR REPLACE FUNCTION public.blueprint_product_availability_internal(p_product bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE p eshop.products; c record; total bigint; occupied bigint; cap bigint; available bigint:=2147483647; capacity bigint:=2147483647;
BEGIN
 SELECT * INTO p FROM eshop.products WHERE id=p_product;
 IF NOT FOUND THEN RETURN jsonb_build_object('capacity',0,'available',0,'reason','PRODUCT_NOT_FOUND'); END IF;
 IF coalesce(p.maximum,0)>0 THEN
  capacity:=p.maximum;
  available:=greatest(0,p.maximum-(SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id));
 END IF;
 FOR c IN SELECT pic.inventory_context,pic.quantity,ip.sellable_capacity FROM eshop.product_inventory_contexts pic
  JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE pic.product=p.id LOOP
  SELECT count(*),count(*) FILTER(WHERE order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>statement_timestamp()))
   INTO total,occupied FROM eshop.spots WHERE inventory_context=c.inventory_context;
  cap:=least(total,coalesce(c.sellable_capacity,total));
  capacity:=least(capacity,cap/greatest(c.quantity,1));
  available:=least(available,greatest(0,cap-occupied)/greatest(c.quantity,1));
 END LOOP;
 RETURN jsonb_build_object('capacity',capacity,'available',CASE WHEN p.is_hidden THEN 0 ELSE available END,
  'reason',CASE WHEN p.is_hidden THEN 'PRODUCT_HIDDEN' WHEN available=0 THEN 'PRODUCT_CAPACITY_EXCEEDED' ELSE NULL END);
END $$;
CREATE OR REPLACE FUNCTION public.blueprint_area_availability_internal(p_blueprint bigint,p_form bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('nodeId',b.node_id,'productId',b.product,'inventoryContextId',b.inventory_context)||
  CASE WHEN p_form IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
   WHERE ff.form=p_form AND p.id=b.product AND ff.type='product_type' AND ff.is_ticket_field AND NOT ff.is_hidden)
  THEN jsonb_build_object('capacity',(public.blueprint_product_availability_internal(b.product)->'capacity'),'available',0,'reason','PRODUCT_NOT_IN_FORM')
  ELSE public.blueprint_product_availability_internal(b.product) END ORDER BY b.node_id),'[]')
 FROM eshop.blueprint_area_bindings b WHERE b.blueprint=p_blueprint
$$;
REVOKE ALL ON FUNCTION public.blueprint_product_availability_internal(bigint),public.blueprint_area_availability_internal(bigint,bigint) FROM PUBLIC,anon,authenticated;
