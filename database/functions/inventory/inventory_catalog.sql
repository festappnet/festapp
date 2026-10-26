-- Shared administration facts. Counts refer to physical/allocated spots per
-- inventory context, not people, tickets or distinct orders. Holds are disjoint.
CREATE OR REPLACE FUNCTION public.get_inventory_context_facts_internal(p_occasion bigint,p_pools bigint[],p_contexts bigint[] DEFAULT NULL)
RETURNS TABLE(context_id bigint,inventory_pool bigint,physical_count bigint,allocated_count bigint,unassigned_count bigint,held_count bigint)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT ic.id,ic.inventory_pool,count(s.id),
   count(s.id) FILTER(WHERE s.order_product_ticket IS NOT NULL),
   count(s.id) FILTER(WHERE s.order_product_ticket IS NOT NULL AND coalesce(s.resource,rs.resource) IS NULL),
   count(s.id) FILTER(WHERE s.order_product_ticket IS NULL AND s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp())
 FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
 LEFT JOIN eshop.spots s ON s.inventory_context=ic.id
 LEFT JOIN public.resource_slots rs ON rs.id=s.resource_slot
 WHERE ip.occasion=p_occasion AND ip.id=ANY(p_pools) AND (p_contexts IS NULL OR ic.id=ANY(p_contexts))
 GROUP BY ic.id,ic.inventory_pool
$$;
REVOKE ALL ON FUNCTION public.get_inventory_context_facts_internal(bigint,bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_inventory_pool_rows_internal(p_occasion bigint,p_ids bigint[],p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH context_totals AS (
  SELECT inventory_pool,count(*) context_count,sum(physical_count) physical_count,sum(allocated_count) allocated_count,
   sum(unassigned_count) unassigned_count,sum(held_count) held_count
  FROM public.get_inventory_context_facts_internal(p_occasion,p_ids) GROUP BY inventory_pool
 ), resource_totals AS (
  SELECT inventory_pool,count(*) resource_count,sum(capacity) resource_capacity FROM public.resources
  WHERE inventory_pool=ANY(p_ids) GROUP BY inventory_pool
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',ip.id,'occasion',ip.occasion,'title',ip.title,
  'created_at',ip.created_at,'updated_at',ip.updated_at,'type',ip.type,'sellable_capacity',ip.sellable_capacity,
  'aggregate_version',coalesce(v.version,0),'context_count',coalesce(c.context_count,0),
  'physical_count',coalesce(c.physical_count,0),'allocated_count',coalesce(c.allocated_count,0),
  'unassigned_count',coalesce(c.unassigned_count,0),'held_count',coalesce(c.held_count,0),
  'resource_count',coalesce(r.resource_count,0),'resource_capacity',coalesce(r.resource_capacity,0)) ORDER BY CASE WHEN p_editor THEN ip.created_at END,ip.id),'[]')
 FROM public.inventory_pools ip LEFT JOIN context_totals c ON c.inventory_pool=ip.id LEFT JOIN resource_totals r ON r.inventory_pool=ip.id
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='inventory_pool' AND v.scope_type='occasion'
  AND v.scope_id=p_occasion AND v.aggregate_id=ip.id::text
 WHERE ip.id=ANY(p_ids) AND ip.occasion=p_occasion
$$;
REVOKE ALL ON FUNCTION public.get_inventory_pool_rows_internal(bigint,bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_inventory_context_rows_internal(p_occasion bigint,p_pools bigint[],p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; next_id bigint; rows jsonb;
BEGIN
 IF p_limit IS NOT NULL AND (p_limit<1 OR p_limit>100) OR p_after IS NOT NULL AND p_after<1 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid inventory context page'; END IF;
 SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ids FROM (
  SELECT ic.id FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
  WHERE ip.occasion=p_occasion AND ip.id=ANY(p_pools) AND (p_after IS NULL OR ic.id>p_after)
  ORDER BY ic.id LIMIT CASE WHEN p_limit IS NULL THEN NULL ELSE p_limit+1 END) selected;
 IF cardinality(ids)>p_limit THEN ids:=ids[1:p_limit];next_id:=ids[p_limit]; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',ic.id,'inventory_pool',ic.inventory_pool,
   'title',ic.title,'block_date',ic.block_date,'order',ic."order",
   'physical_count',f.physical_count,'allocated_count',f.allocated_count,'unassigned_count',f.unassigned_count,'held_count',f.held_count)
   ORDER BY CASE WHEN p_limit IS NULL THEN ic."order" END NULLS LAST,ic.id),'[]') INTO rows
 FROM public.inventory_contexts ic JOIN public.get_inventory_context_facts_internal(p_occasion,p_pools,ids) f ON f.context_id=ic.id;
 RETURN jsonb_build_object('inventory_contexts',rows,'nextCursor',next_id);
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_context_rows_internal(bigint,bigint[],bigint,integer) FROM PUBLIC,anon,authenticated,service_role;

-- NULL limit is the explicit full-summary UI mode; it never includes spot rows.
CREATE OR REPLACE FUNCTION public.get_inventory_catalog_data_internal(p_occasion bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; next_id bigint; contexts jsonb:='[]'; occasion_data jsonb;
BEGIN
 IF p_limit IS NOT NULL AND (p_limit<1 OR p_limit>100) OR p_after IS NOT NULL AND p_after<1 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid inventory pool page'; END IF;
 SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ids FROM (
  SELECT id FROM public.inventory_pools WHERE occasion=p_occasion AND (p_after IS NULL OR id>p_after)
  ORDER BY id LIMIT CASE WHEN p_limit IS NULL THEN NULL ELSE p_limit+1 END) selected;
 IF cardinality(ids)>p_limit THEN ids:=ids[1:p_limit];next_id:=ids[p_limit]; END IF;
 IF p_limit IS NULL THEN contexts:=public.get_inventory_context_rows_internal(p_occasion,ids)->'inventory_contexts'; END IF;
 SELECT jsonb_build_object('id',o.id,'title',o.title) INTO occasion_data FROM public.occasions o WHERE o.id=p_occasion;
 RETURN jsonb_build_object('occasionId',p_occasion,'occasion',occasion_data,'pools',public.get_inventory_pool_rows_internal(p_occasion,ids,p_limit IS NULL),
  'inventory_contexts',contexts,'nextCursor',next_id,'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_catalog_data_internal(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_inventory_catalog(p_organization bigint,p_occasion bigint DEFAULT NULL,p_unit bigint DEFAULT NULL,
 p_occasion_link text DEFAULT NULL,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50,p_mode text DEFAULT 'page')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint:=p_occasion; result jsonb;
BEGIN
 IF p_mode IS NULL OR p_mode NOT IN ('page','summary') OR p_mode='page' AND p_limit IS NULL
  OR p_mode='summary' AND (p_limit IS NOT NULL OR p_after IS NOT NULL) THEN
  RAISE invalid_parameter_value USING MESSAGE='explicit inventory read mode required'; END IF;
 IF p_occasion_link IS NOT NULL THEN
  oc:=public.resolve_occasion_link_internal(p_occasion_link);
  IF p_occasion IS NOT NULL AND p_occasion IS DISTINCT FROM oc THEN RAISE insufficient_privilege USING MESSAGE='inventory context unavailable'; END IF;
 END IF;
 PERFORM public.check_product_catalog_scope_internal(oc,p_organization,p_unit,false,true);
 result:=public.get_inventory_catalog_data_internal(oc,p_after,p_limit);
 PERFORM public.check_product_catalog_scope_internal(oc,p_organization,p_unit,false,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_catalog(bigint,bigint,bigint,text,bigint,integer,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_inventory_catalog(bigint,bigint,bigint,text,bigint,integer,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_inventory_context_catalog(p_occasion bigint,p_organization bigint,p_unit bigint,p_pool bigint,
 p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_limit IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='bounded context page required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 PERFORM 1 FROM public.inventory_pools WHERE id=p_pool AND occasion=p_occasion FOR SHARE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='inventory pool unavailable'; END IF;
 result:=jsonb_build_object('occasionId',p_occasion,'poolId',p_pool,'readAt',statement_timestamp())
  ||public.get_inventory_context_rows_internal(p_occasion,ARRAY[p_pool],p_after,p_limit);
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_context_catalog(bigint,bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_inventory_context_catalog(bigint,bigint,bigint,bigint,bigint,integer) TO authenticated;
