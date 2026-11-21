-- Forms publish the only eligible sources. A seat selection represents its
-- entire selection unit; an admission change cannot displace another holder.
CREATE OR REPLACE FUNCTION public.order_admission_targets_internal(p_form bigint)
RETURNS TABLE(product_id bigint,spot_id bigint,spots bigint[],title text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH source AS (
   SELECT f.id,f.occasion,CASE WHEN jsonb_path_exists(o.features,
     '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN f.blueprint END AS blueprint
   FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form
 ), products AS (
   SELECT p.* FROM source f JOIN eshop.products p ON p.occasion=f.occasion AND NOT p.is_hidden
   JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.occasion=f.occasion AND pt.type='spot'
 )
 SELECT p.id,s.id,members.ids,concat_ws(' · ',p.title,group_title.title)
 FROM source f JOIN eshop.blueprint_seat_bindings sb ON sb.blueprint=f.blueprint
 JOIN eshop.spots s ON s.id=sb.spot AND s.blueprint=f.blueprint AND s.occasion=f.occasion
 JOIN products p ON p.id=s.product
 CROSS JOIN LATERAL (SELECT public.blueprint_selection_unit_spots_internal(s.id) AS ids) members
 CROSS JOIN LATERAL (SELECT string_agg(x.title,', ' ORDER BY x.id) AS title FROM eshop.spots x WHERE x.id=ANY(members.ids)) group_title
 WHERE s.id=members.ids[1]
 UNION ALL
 SELECT p.id,NULL::bigint,'{}'::bigint[],p.title
 FROM products p CROSS JOIN source f
 WHERE (f.blueprint IS NULL AND EXISTS(SELECT 1 FROM public.form_fields ff
   WHERE ff.form=f.id AND ff.product_type=p.product_type AND NOT ff.is_hidden)
   AND NOT EXISTS(SELECT 1 FROM eshop.spots seat JOIN eshop.blueprint_seat_bindings sb ON sb.spot=seat.id
     JOIN public.forms owner ON owner.blueprint=sb.blueprint
     WHERE seat.product=p.id AND owner.occasion=f.occasion))
 OR (f.blueprint IS NOT NULL AND EXISTS(
   SELECT 1 FROM eshop.blueprint_area_bindings ab JOIN eshop.product_inventory_contexts pic
     ON pic.product=ab.product AND pic.inventory_context=ab.inventory_context AND pic.quantity>0
   WHERE ab.blueprint=f.blueprint AND ab.product=p.id
 ) AND NOT EXISTS(SELECT 1 FROM eshop.spots seat JOIN eshop.blueprint_seat_bindings sb ON sb.spot=seat.id
   WHERE seat.product=p.id AND sb.blueprint=f.blueprint))
$$;
REVOKE ALL ON FUNCTION public.order_admission_targets_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_order_admission_options_v1(p_order_id bigint,p_ticket_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; blocker text; options jsonb; fields jsonb; source_spot bigint; source_product bigint; source_quantity integer:=1;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 IF o.id IS NULL OR auth.uid() IS NULL OR public.can_write_orders(o.occasion) IS NOT TRUE OR public.can_read_orders(o.occasion) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='order editor required';
 END IF;
 blocker:=public.order_admission_blocker_internal(o.id,p_ticket_id);
 IF blocker IS NOT NULL THEN RETURN jsonb_build_object('code',409,'data',jsonb_build_object('reason',blocker)); END IF;
 SELECT x.product,s.id INTO source_product,source_spot FROM eshop.order_product_ticket x
 JOIN eshop.products p ON p.id=x.product JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.type='spot'
 LEFT JOIN eshop.spots s ON s.order_product_ticket=x.id AND s.blueprint IS NOT NULL
 WHERE x."order"=o.id AND x.ticket=p_ticket_id;
 IF source_spot IS NOT NULL THEN
   source_quantity:=cardinality(public.blueprint_selection_unit_spots_internal(source_spot));
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'spotId',spot_id,'title',target.title,
    'quantity',greatest(1,cardinality(spots)),'price',p.price,'currency_code',p.currency_code)
    ORDER BY target.title,product_id,spot_id),'[]') INTO options
 FROM public.order_admission_targets_internal(o.form) target JOIN eshop.products p ON p.id=target.product_id
 WHERE p.currency_code=o.currency_code AND (source_product IS DISTINCT FROM product_id OR source_spot IS DISTINCT FROM spot_id)
   AND (p_ticket_id IS NULL OR greatest(1,cardinality(spots))=source_quantity)
   AND (spot_id IS NOT NULL OR (public.blueprint_product_availability_internal(p.id)->>'available')::bigint>0)
   AND NOT EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
     WHERE s.id=ANY(spots) AND (s.order_product_ticket IS NOT NULL OR sb.blocked OR
       s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()));
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'type',f.type,'title',coalesce(f.title,pt.title),'required',f.is_required,
   'data',f.data,'options',CASE WHEN f.type='product_type' THEN (
     SELECT coalesce(jsonb_agg(jsonb_build_object('productId',p.id,'title',p.title,
       'price',p.price,'currency_code',p.currency_code) ORDER BY p.title,p.id),'[]')
     FROM eshop.products p WHERE p.product_type=f.product_type AND p.occasion=o.occasion AND NOT p.is_hidden)
   ELSE coalesce(f.data->'options','[]') END) ORDER BY f."order",f.id),'[]') INTO fields
 FROM public.form_fields f LEFT JOIN eshop.product_types pt ON pt.id=f.product_type
 WHERE p_ticket_id IS NULL AND f.form=o.form AND f.is_ticket_field AND NOT f.is_hidden
   AND f.type NOT IN ('spot','ticket','html') AND pt.type IS DISTINCT FROM 'spot';
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object('options',options,'fields',fields));
END $$;
REVOKE ALL ON FUNCTION public.get_order_admission_options_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_order_admission_options_v1(bigint,bigint) TO authenticated;
