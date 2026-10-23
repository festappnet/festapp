-- Share inventory card facts and recheck live read rights before return.
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

CREATE OR REPLACE FUNCTION public.get_inventory_pools_by_occasion_link(p_occasion_link text)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_occasion_data jsonb;
    v_pools_data jsonb;
    v_inventory_contexts_data jsonb;
    v_spots_data jsonb;
    result jsonb;
    catalog jsonb;
BEGIN
    -- Canonical merges may contain the same legacy link in multiple tenants.
    SELECT o.id
    INTO v_occasion_id
    FROM public.occasions o
    WHERE o.id = public.resolve_occasion_link_internal(p_occasion_link)
      AND o.organization = (
        SELECT ui.organization
        FROM public.user_info ui
        WHERE ui.id = auth.uid()
      );
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion with link % not found.', p_occasion_link;
    END IF;

    -- Permission check to ensure the user can view data for this occasion.
    IF NOT COALESCE((
        SELECT ou.is_editor_order_view
        FROM public.occasion_users ou
        WHERE ou."user" = auth.uid()
          AND ou.occasion = v_occasion_id
    ), false) THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Get the full occasion object
    SELECT to_jsonb(o) INTO v_occasion_data FROM public.occasions o WHERE id = v_occasion_id;

    -- Released clients still need the old raw spot array. Metadata and counts
    -- delegate to the same projection as the current summary UI/MCP readers.
    catalog:=public.get_inventory_catalog_data_internal(v_occasion_id);
    SELECT coalesce(jsonb_agg(p.value||jsonb_build_object('description',ip.description,'data',ip.data)
      ORDER BY ip.created_at,ip.id),'[]') INTO v_pools_data
      FROM jsonb_array_elements(catalog->'pools') p(value) JOIN public.inventory_pools ip ON ip.id=(p.value->>'id')::bigint WHERE ip.occasion=v_occasion_id;
    SELECT coalesce(jsonb_agg(c.value||jsonb_build_object('data',ic.data) ORDER BY ic."order" NULLS LAST,ic.id),'[]') INTO v_inventory_contexts_data
      FROM jsonb_array_elements(catalog->'inventory_contexts') c(value) JOIN public.inventory_contexts ic ON ic.id=(c.value->>'id')::bigint
      JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE ip.occasion=v_occasion_id;

    -- Aggregate all spots that belong to any context within the occasion's pools
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'secret', s.secret,
        'secret_expiration_time', s.secret_expiration_time,
        'order_product_ticket', s.order_product_ticket,
        'inventory_context', s.inventory_context,
        'resource', s.resource,
        'state', s.state
    ) ORDER BY s.id), '[]'::jsonb)
    INTO v_spots_data
    FROM eshop.spots s
    WHERE s.inventory_context IN (
        SELECT id FROM public.inventory_contexts WHERE inventory_pool IN (
            SELECT id FROM public.inventory_pools WHERE occasion = v_occasion_id
        )
    );

    -- Construct the final bundle object with the new data
    result := jsonb_build_object(
        'occasion', v_occasion_data,
        'pools', v_pools_data,
        'inventory_contexts', v_inventory_contexts_data,
        'spots', v_spots_data
    );

    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- Shared UI/MCP boundary. Existing product commands remain the sole owners of
-- business rules, receipts, inventory recalculation and sync publication.
CREATE OR REPLACE FUNCTION public.check_product_catalog_scope_internal(
 p_occasion bigint,p_organization bigint,p_unit bigint,p_write boolean,p_lock boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_lock THEN
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization
   WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE OF o;
 ELSE
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization
   WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit);
 END IF;
 IF NOT FOUND OR public.can_read_orders(p_occasion) IS DISTINCT FROM TRUE
  OR (p_write AND public.can_write_orders(p_occasion) IS DISTINCT FROM TRUE) THEN
  RAISE insufficient_privilege USING MESSAGE='product context unavailable';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_product_catalog_scope_internal(bigint,bigint,bigint,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_product_catalog(p_organization bigint,p_occasion bigint DEFAULT NULL,
 p_unit bigint DEFAULT NULL,p_occasion_link text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint:=p_occasion; result jsonb;
BEGIN
 IF p_occasion_link IS NOT NULL THEN
  oc:=public.resolve_occasion_link_internal(p_occasion_link);
  IF p_occasion IS NOT NULL AND oc IS DISTINCT FROM p_occasion THEN
   RAISE insufficient_privilege USING MESSAGE='product context unavailable'; END IF;
 END IF;
 PERFORM public.check_product_catalog_scope_internal(oc,p_organization,p_unit,false,true);
 result:=jsonb_build_object('occasionId',oc,'catalog',public.get_product_catalog_data_internal(oc));
 PERFORM public.check_product_catalog_scope_internal(oc,p_organization,p_unit,false,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_product_catalog(bigint,bigint,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_catalog(bigint,bigint,bigint,text) TO authenticated;

-- Bounded read mode of the same catalog owner. Keep the four-argument
-- editor API for released clients; no overload with ambiguous defaults.
CREATE OR REPLACE FUNCTION public.get_product_catalog_page(p_organization bigint,p_occasion bigint,
 p_unit bigint DEFAULT NULL,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE catalog jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR p_after IS NOT NULL AND p_after<1 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid catalog page';
 END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 catalog:=public.get_product_catalog_data_internal(p_occasion,p_after,p_limit)::jsonb;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'nextCursor',catalog->'nextCursor','catalog',
   catalog-ARRAY['nextCursor','server_time','price_waves','inventory_pools']);
END $$;
REVOKE ALL ON FUNCTION public.get_product_catalog_page(bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_catalog_page(bigint,bigint,bigint,bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_product(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_action text,p_product jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; product_id bigint; receipt_name text; result jsonb;
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true);
 IF p_action IS NULL OR p_action NOT IN ('save','delete','contexts') OR p_product IS NULL
  OR jsonb_typeof(p_product)<>'object' OR octet_length(p_product::text)>524288 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid product command'; END IF;
 product_id:=NULLIF(p_product->>'id','')::bigint;
 receipt_name:=CASE p_action WHEN 'save' THEN 'inventory.product.save' WHEN 'delete' THEN 'inventory.product.delete' ELSE 'inventory.product.contexts' END;
 -- Retained receipt is the authoritative occasion after a successful deletion.
 SELECT occasion INTO oc FROM public.client_mutation_receipts
  WHERE command_id=p_command_id AND actor_id=auth.uid() AND command_name=receipt_name;
 IF NOT FOUND THEN
  IF product_id IS NOT NULL THEN SELECT p.occasion INTO oc FROM eshop.products p WHERE p.id=product_id;
  ELSIF p_action='save' THEN SELECT pt.occasion INTO oc FROM eshop.product_types pt WHERE pt.id=(p_product->>'product_type')::bigint;
  END IF;
 END IF;
 IF oc IS DISTINCT FROM p_occasion OR (p_product->>'occasion' IS NOT NULL AND (p_product->>'occasion')::bigint IS DISTINCT FROM p_occasion)
  OR (p_product->>'product_type' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=(p_product->>'product_type')::bigint AND pt.occasion=p_occasion)) THEN
  RAISE insufficient_privilege USING MESSAGE='product unavailable'; END IF;
 IF product_id IS NOT NULL AND (p_product->>'expected_aggregate_version' IS NULL
   OR (p_product->>'expected_aggregate_version')::bigint<0) THEN
  RAISE invalid_parameter_value USING MESSAGE='original product version required'; END IF;
 IF p_action='save' THEN
  result:=public.update_product_client_sync_v1(p_product,p_command_id);
 ELSIF p_action='delete' THEN
  result:=public.delete_product_client_sync_v1(product_id,p_command_id,(p_product->>'expected_aggregate_version')::bigint);
 ELSE
  result:=public.update_product_inventory_contexts_client_sync_v1(product_id,
   jsonb_build_object('expected_aggregate_version',p_product->'expected_aggregate_version','contexts',p_product->'inventory_contexts'),p_command_id);
 END IF;
 -- Validate and lock the live tenant/organizer after domain locking, including
 -- receipt replay. A concurrent move or rights change rolls back ALL effects.
 -- Do not acquire organizer locks before the canonical receipt/order locks.
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_product(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_product(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_product_schedule(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_limit IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='bounded wave page required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 result:=jsonb_build_object('occasionId',p_occasion)||public.get_product_price_waves_internal(p_occasion,p_after,p_limit);
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_product_schedule(bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_schedule(bigint,bigint,bigint,bigint,integer) TO authenticated;
