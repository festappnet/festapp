-- Canonical R2 image record admission; legacy Storage policy history stays in its installed migration.
CREATE INDEX IF NOT EXISTS images_occasion_abuse ON public.images(occasion) WHERE occasion IS NOT NULL;
CREATE INDEX IF NOT EXISTS images_unit_abuse ON public.images(unit) WHERE unit IS NOT NULL;
CREATE OR REPLACE FUNCTION public.admit_image_record_budget_internal(p_link text,p_occasion bigint,p_unit bigint) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint; policy jsonb; scopes jsonb; r jsonb; unit_count bigint; org_count bigint;
BEGIN
 IF p_link IS NULL OR p_link !~ '^https://(a\.)?img\.festapp\.net/images/[A-Za-z0-9_./-]+$' THEN
  RAISE invalid_parameter_value USING MESSAGE='canonical public image URL required'; END IF;
 IF p_occasion IS NOT NULL THEN SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion;
 ELSE SELECT id,organization INTO un,org FROM public.units WHERE id=p_unit; END IF;
 policy:=public.abuse_effective_rules_v1('image.records',un,org);
 scopes:=jsonb_build_object('actor',auth.uid(),'unit',un,'organization',org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  IF r->>'kind' IN ('rolling','occupancy') THEN
   PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
  END IF;
 END LOOP;
 SELECT count(*) FILTER(WHERE coalesce(i.unit,o.unit)=un),count(*) INTO unit_count,org_count
 FROM public.images i LEFT JOIN public.occasions o ON o.id=i.occasion LEFT JOIN public.units u ON u.id=i.unit
 WHERE coalesce(o.organization,u.organization)=org;
 PERFORM public.abuse_charge_v1(policy,scopes,jsonb_build_object('image.records.link.bytes',octet_length(p_link),
  'image.records.stored.unit',unit_count+1,'image.records.stored.organization',org_count+1));
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_record_v1(p_link text,p_occasion bigint,p_unit bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR (p_occasion IS NULL)=(p_unit IS NULL) OR public.check_upload_permission(p_occasion,p_unit) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='exactly one authorized image owner required'; END IF;
 PERFORM public.admit_image_record_budget_internal(p_link,p_occasion,p_unit);
END $$;
REVOKE ALL ON FUNCTION public.admit_image_record_budget_internal(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.admit_image_record_v1(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE INSERT,UPDATE ON public.images FROM PUBLIC,anon,authenticated;
