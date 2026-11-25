-- Evaluate the checked form editor and administrative order projections once.

-- SOURCE: eshop_forms/admin_form_reads.sql
CREATE OR REPLACE FUNCTION public.get_form_authoring_snapshot_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 -- The projection uses bundle repeatedly. Compute the expensive builder once.
 WITH b AS MATERIALIZED (SELECT public.get_form_editor_bundle_internal(p_form,true) bundle)
 SELECT jsonb_build_object('form',(bundle->'data'->'form')-ARRAY['key','link','organizationIdentity','created_at'],
  'fields',bundle->'data'->'form_fields','productTypes',bundle->'data'->'product_types','products',bundle->'data'->'products',
  'productVersions',(SELECT coalesce(jsonb_object_agg(p->>'id',p->'aggregate_version'),'{}') FROM jsonb_array_elements(bundle->'data'->'products') p),
  'productTypeVersions',(SELECT coalesce(jsonb_object_agg(p->>'id',p->'aggregate_version'),'{}') FROM jsonb_array_elements(bundle->'data'->'product_types') p))
 FROM b WHERE (bundle->>'code')::int=200;
$$;

-- SOURCE: eshop_forms/admin_form_orders.sql
CREATE OR REPLACE FUNCTION public.form_order_facts_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH s AS MATERIALIZED (SELECT public.get_form_authoring_snapshot_internal(p_form) snap)
 SELECT jsonb_build_object('form',(SELECT to_jsonb(f)-ARRAY['key','link','created_at'] FROM public.forms f WHERE id=p_form),
  'fields',snap->'fields','products',snap->'products','productTypes',snap->'productTypes')
 FROM s;
$$;
