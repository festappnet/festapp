-- One usage owner for counts and destructive guards. The FK owns current
-- responses; historical UUID references still prevent destructive deletion.
CREATE OR REPLACE FUNCTION public.get_form_usage_rows_internal(p_forms bigint[])
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH selected AS MATERIALIZED (SELECT id,key FROM public.forms WHERE id=ANY(p_forms)), refs AS (
  SELECT q.form form_id,q.id order_id,true is_response FROM eshop.orders q WHERE q.form=ANY(p_forms)
  UNION ALL
  SELECT f.id,q.id,q.form IS NULL FROM eshop.orders q JOIN selected f ON q.data->>'form'=f.key::text
 ), unique_refs AS (
  SELECT form_id,order_id,bool_or(is_response) is_response FROM refs GROUP BY form_id,order_id
 ), totals AS (
  SELECT form_id,count(*) blocking_orders,count(*) FILTER(WHERE is_response) response_count FROM unique_refs GROUP BY form_id
 )
 SELECT coalesce(jsonb_object_agg(f.id::text,jsonb_build_object('response_count',coalesce(t.response_count,0),
  'blocking_orders',coalesce(t.blocking_orders,0))),'{}') FROM selected f LEFT JOIN totals t ON t.form_id=f.id;
$$;
REVOKE ALL ON FUNCTION public.get_form_usage_rows_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_form_usage_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT public.get_form_usage_rows_internal(ARRAY[p_form])->p_form::text;
$$;
REVOKE ALL ON FUNCTION public.get_form_usage_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Private projection shared by current editor acknowledgements and MCP. Public
-- keys/links and bank-account details are not part of this authoring snapshot.
CREATE OR REPLACE FUNCTION public.get_form_authoring_snapshot_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('form',(bundle->'data'->'form')-ARRAY['key','link','organizationIdentity','created_at'],
  'fields',bundle->'data'->'form_fields','productTypes',bundle->'data'->'product_types','products',bundle->'data'->'products',
  'productVersions',(SELECT coalesce(jsonb_object_agg(p->>'id',p->'aggregate_version'),'{}') FROM jsonb_array_elements(bundle->'data'->'products') p),
  'productTypeVersions',(SELECT coalesce(jsonb_object_agg(p->>'id',p->'aggregate_version'),'{}') FROM jsonb_array_elements(bundle->'data'->'product_types') p))
 FROM (SELECT public.get_form_editor_bundle_internal(p_form,true) bundle) b WHERE (bundle->>'code')::int=200;
$$;
REVOKE ALL ON FUNCTION public.get_form_authoring_snapshot_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Apply the page before capacity/history/field work. Unbounded mode exists only
-- for the existing full administration list, using the identical row projection.
CREATE OR REPLACE FUNCTION public.get_form_catalog_rows_internal(p_occasion bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH selected AS MATERIALIZED (
  SELECT * FROM public.forms WHERE occasion=p_occasion AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT p_limit
 ), usage AS MATERIALIZED (
  SELECT public.get_form_usage_rows_internal(ARRAY(SELECT id FROM selected)) rows
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'data',f.data,'key',f.key,'link',f.link,
  'occasion',f.occasion,'type',f.type,'is_open',f.is_open,'blueprint',f.blueprint,
  'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
  'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
  'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
  'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions v WHERE v.aggregate_type='form' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=f.id::text),0),
  'response_count',usage.rows->f.id::text->'response_count',
  'fields',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',ff.id,'type',ff.type,'is_ticket_field',ff.is_ticket_field) ORDER BY coalesce(ff."order",0),ff.id),'[]') FROM public.form_fields ff WHERE ff.form=f.id)) ORDER BY f.id),'[]')
 FROM selected f CROSS JOIN usage;
$$;
REVOKE ALL ON FUNCTION public.get_form_catalog_rows_internal(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_form_authoring_scope_internal(p_occasion bigint,p_organization bigint,p_unit bigint,p_operation text,p_lock boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE allowed boolean;
BEGIN
 IF p_lock THEN
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization
   WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE OF o;
 ELSE
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization
   WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit);
 END IF;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='form hierarchy unavailable'; END IF;
 allowed:=CASE p_operation WHEN 'list' THEN public.can_read_form_catalog(p_occasion)
  WHEN 'inspect' THEN public.can_read_form_catalog(p_occasion)
  WHEN 'source' THEN public.can_copy_form_source(p_occasion)
  WHEN 'duplicate' THEN public.can_copy_form_target(p_occasion)
  WHEN 'create' THEN public.can_author_forms(p_occasion)
  WHEN 'save' THEN public.can_author_forms(p_occasion)
  WHEN 'delete' THEN public.can_author_forms(p_occasion) ELSE false END;
 IF allowed IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='form operation denied'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_form_authoring_scope_internal(bigint,bigint,bigint,text,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_form_catalog_page(p_occasion bigint,p_organization bigint,p_unit bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; last_id bigint; next_id bigint; result jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR (p_after IS NOT NULL AND p_after<1) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid form page'; END IF;
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,'list',true);
 rows:=public.get_form_catalog_rows_internal(p_occasion,p_after,p_limit);
 SELECT max((r->>'id')::bigint) INTO last_id FROM jsonb_array_elements(rows) r;
 IF EXISTS(SELECT 1 FROM public.forms WHERE occasion=p_occasion AND id>last_id) THEN next_id:=last_id; END IF;
 SELECT coalesce(jsonb_agg(r-ARRAY['key','link','data'] ORDER BY (r->>'id')::bigint),'[]') INTO rows FROM jsonb_array_elements(rows) r;
 result:=jsonb_build_object('occasionId',p_occasion,'forms',rows,'nextCursor',next_id);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='form page too large'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_catalog_page(bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_catalog_page(bigint,bigint,bigint,bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_form_for_authoring(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,'inspect',true);
 IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
 result:=public.get_form_authoring_snapshot_internal(p_form);
 IF octet_length(result::text)>1048576 OR jsonb_array_length(result->'fields')>500 THEN RAISE program_limit_exceeded USING MESSAGE='form snapshot too large'; END IF;
 RETURN jsonb_build_object('occasionId',p_occasion,'authoring',result);
END $$;
REVOKE ALL ON FUNCTION public.get_form_for_authoring(bigint,bigint,bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_for_authoring(bigint,bigint,bigint,bigint) TO authenticated;
