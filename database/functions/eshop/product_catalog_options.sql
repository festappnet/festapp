-- Shared editor-choice projections. NULL IDs is an explicit full UI metadata
-- request; an empty array is an empty product page, never a request for all rows.
CREATE OR REPLACE FUNCTION public.get_product_type_rows_internal(p_occasion bigint,p_ids bigint[] DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',pt.id,'type',pt.type,'title',pt.title) ORDER BY pt.id),'[]')
 FROM eshop.product_types pt WHERE pt.occasion=p_occasion AND (p_ids IS NULL OR pt.id=ANY(p_ids))
$$;
REVOKE ALL ON FUNCTION public.get_product_type_rows_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_product_context_rows_internal(p_occasion bigint,p_ids bigint[] DEFAULT NULL,p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg((CASE WHEN p_editor THEN to_jsonb(ic) ELSE jsonb_build_object(
  'id',ic.id,'title',ic.title,'inventory_pool',ic.inventory_pool,'block_date',ic.block_date) END)
  ||jsonb_build_object('pool_title',ip.title,'pool_type',ip.type) ORDER BY ic.id),'[]')
 FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
 WHERE ip.occasion=p_occasion AND (p_ids IS NULL OR ic.id=ANY(p_ids))
$$;
REVOKE ALL ON FUNCTION public.get_product_context_rows_internal(bigint,bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_product_catalog_options(p_occasion bigint,p_organization bigint,p_unit bigint,p_kind text,
 p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[];next_id bigint;rows jsonb;
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN ('product_types','inventory_contexts') OR p_limit IS NULL OR p_limit<1 OR p_limit>100
  OR p_after IS NOT NULL AND p_after<1 THEN RAISE invalid_parameter_value USING MESSAGE='invalid product option page'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 IF p_kind='product_types' THEN
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ids FROM (
   SELECT id FROM eshop.product_types WHERE occasion=p_occasion AND (p_after IS NULL OR id>p_after)
   ORDER BY id LIMIT p_limit+1) selected;
 ELSE
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ids FROM (
   SELECT ic.id FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
   WHERE ip.occasion=p_occasion AND (p_after IS NULL OR ic.id>p_after) ORDER BY ic.id LIMIT p_limit+1) selected;
 END IF;
 IF cardinality(ids)>p_limit THEN ids:=ids[1:p_limit];next_id:=ids[p_limit]; END IF;
 IF p_kind='product_types' THEN rows:=public.get_product_type_rows_internal(p_occasion,ids);
 ELSE rows:=public.get_product_context_rows_internal(p_occasion,ids); END IF;
 IF octet_length(rows::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='product option page exceeds payload limit; use a smaller limit'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'kind',p_kind,'options',rows,'nextCursor',next_id,'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.get_product_catalog_options(bigint,bigint,bigint,text,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_catalog_options(bigint,bigint,bigint,text,bigint,integer) TO authenticated;
