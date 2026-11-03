-- Only the data actually copied by the existing SQL implementation is priced.
-- The outer LIMIT bounds row work; a post-copy check catches concurrent growth
-- before commit. No order, ticket, membership or second copy workflow is added.
CREATE OR REPLACE FUNCTION public.admit_occasion_copy_v1(p_source bigint,p_unit bigint,p_org bigint,p_policy jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE policy jsonb; cap bigint; items bigint; bytes bigint;
BEGIN
 policy:=coalesce(p_policy,public.abuse_effective_rules_v1('occasion.copy',p_unit,p_org));
 SELECT (x->>'base_limit')::bigint INTO cap FROM jsonb_array_elements(policy->'rules') x WHERE x->>'rule_key'='occasion.copy.items';
 IF cap IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 SELECT count(*),coalesce(sum(size),0) INTO items,bytes FROM (
  SELECT octet_length(to_jsonb(t)::text) AS size FROM public.occasions t WHERE id=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.email_templates t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.information_hidden t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.information t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.role_info t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.places t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.exclusive_groups t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.events t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.event_groups t WHERE event_parent IN (SELECT id FROM public.events WHERE occasion=p_source)
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.event_roles t WHERE event IN (SELECT id FROM public.events WHERE occasion=p_source)
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.exclusive_events t WHERE event IN (SELECT id FROM public.events WHERE occasion=p_source)
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM eshop.blueprints t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM eshop.product_types t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM eshop.products t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM eshop.spots t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.forms t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.form_fields t WHERE form IN (SELECT id FROM public.forms WHERE occasion=p_source)
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.inventory_pools t WHERE occasion=p_source
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.inventory_contexts t WHERE inventory_pool IN (SELECT id FROM public.inventory_pools WHERE occasion=p_source)
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.resources t WHERE inventory_pool IN (SELECT id FROM public.inventory_pools WHERE occasion=p_source)
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM public.resource_slots t WHERE resource IN (SELECT id FROM public.resources WHERE inventory_pool IN (SELECT id FROM public.inventory_pools WHERE occasion=p_source))
  UNION ALL SELECT octet_length(to_jsonb(t)::text) FROM eshop.product_inventory_contexts t WHERE product IN (SELECT id FROM eshop.products WHERE occasion=p_source)
  LIMIT cap+1
 ) copied_rows;
 PERFORM public.abuse_charge_v1(policy,jsonb_build_object('unit',p_unit,'organization',p_org),
  jsonb_build_object('occasion.copy.items',items,'occasion.copy.bytes',bytes));
END $$;
REVOKE ALL ON FUNCTION public.admit_occasion_copy_v1(bigint,bigint,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_occasion_copy_v1(p_source bigint,p_unit bigint,p_org bigint)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.admit_occasion_copy_v1(p_source,p_unit,p_org,NULL);
$$;
REVOKE ALL ON FUNCTION public.admit_occasion_copy_v1(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
