CREATE OR REPLACE FUNCTION public.get_product_for_authoring_v1(p_product bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint;
BEGIN
 SELECT occasion INTO oc FROM eshop.products WHERE id=p_product;
 IF auth.uid() IS NULL OR oc IS NULL OR public.can_read_orders(oc) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='order editor view required'; END IF;
 RETURN (SELECT jsonb_build_object('id',p.id,'occasion',p.occasion,'product_type',p.product_type,
  'title',p.title,'description',p.description,'price',p.price,'currency_code',p.currency_code,'data',p.data,
  'is_hidden',p.is_hidden,'order',p."order",'maximum',p.maximum,'aggregate_version',coalesce(v.version,0),
  'inventory_contexts',coalesce((SELECT jsonb_agg(jsonb_build_object('inventory_context_id',pic.inventory_context,'quantity',pic.quantity) ORDER BY pic.inventory_context)
    FROM eshop.product_inventory_contexts pic WHERE pic.product=p.id),'[]'))
 FROM eshop.products p LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='product' AND v.scope_type='occasion'
 AND v.scope_id=p.occasion AND v.aggregate_id=p.id::text WHERE p.id=p_product);
END $$;
REVOKE ALL ON FUNCTION public.get_product_for_authoring_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_product_for_authoring_v1(bigint) TO authenticated;
