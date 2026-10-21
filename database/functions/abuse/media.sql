-- The actual IO adapter supplies the measured file size before transform/R2 put.
-- A direct call grants no storage capability and cannot refund committed IO work.
CREATE OR REPLACE FUNCTION public.admit_image_upload_budget_internal(p_bytes bigint,p_occasion_id bigint,p_unit_id bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint; policy jsonb; costs jsonb;
BEGIN
 IF p_bytes IS NULL OR p_bytes<=0 THEN RAISE invalid_parameter_value USING MESSAGE='image bytes required'; END IF;
 IF p_occasion_id IS NOT NULL THEN SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion_id;
 ELSE SELECT id,organization INTO un,org FROM public.units WHERE id=p_unit_id; END IF;
 policy:=public.abuse_effective_rules_v1('image.upload',un,org);
 costs:=jsonb_build_object('image.upload.actor.bytes',p_bytes,'image.upload.unit.bytes',p_bytes,'image.upload.organization.bytes',p_bytes);
 PERFORM public.abuse_charge_v1(policy,jsonb_build_object('actor',auth.uid(),'unit',un,'organization',org),costs);
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_upload_v1(p_bytes bigint,p_occasion_id bigint DEFAULT NULL,p_unit_id bigint DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR (p_occasion_id IS NULL)=(p_unit_id IS NULL)
  OR public.check_upload_permission(p_occasion_id,p_unit_id) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='image editor required'; END IF;
 RETURN public.admit_image_upload_budget_internal(p_bytes,p_occasion_id,p_unit_id);
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_upload_v1(p_bytes bigint,p_occasion_id bigint,p_unit_id bigint,p_profile text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_profile IS DISTINCT FROM 'blueprint-background' OR (p_occasion_id IS NULL)=(p_unit_id IS NULL) OR auth.uid() IS NULL
  OR NOT public.can_upload_blueprint_background(p_occasion_id,p_unit_id) THEN RAISE insufficient_privilege USING MESSAGE='blueprint image editor required'; END IF;
 RETURN public.admit_image_upload_budget_internal(p_bytes,p_occasion_id,p_unit_id);
END $$;
REVOKE ALL ON FUNCTION public.admit_image_upload_v1(bigint,bigint,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_image_upload_v1(bigint,bigint,bigint,text) TO authenticated;
REVOKE ALL ON FUNCTION public.admit_image_upload_budget_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.admit_image_upload_v1(bigint,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_image_upload_v1(bigint,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.admit_external_image_fetch_v1(p_occasion_id bigint DEFAULT NULL,p_unit_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint; policy jsonb; cap bigint;
BEGIN
 IF auth.uid() IS NULL OR (p_occasion_id IS NULL)=(p_unit_id IS NULL)
  OR public.check_upload_permission(p_occasion_id,p_unit_id) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='image editor required'; END IF;
 IF p_occasion_id IS NOT NULL THEN SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion_id;
 ELSE SELECT id,organization INTO un,org FROM public.units WHERE id=p_unit_id; END IF;
 policy:=public.abuse_effective_rules_v1('image.fetch',un,org);
 SELECT (r->>'base_limit')::bigint INTO cap FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='image.fetch.payload.bytes';
 IF cap IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 PERFORM public.abuse_charge_v1(policy,jsonb_build_object('actor',auth.uid(),'unit',un,'organization',org),jsonb_build_object('image.fetch.payload.bytes',cap));
 RETURN jsonb_build_object('allowed',true,'maxBytes',cap);
END $$;
REVOKE ALL ON FUNCTION public.admit_external_image_fetch_v1(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_external_image_fetch_v1(bigint,bigint) TO authenticated;

-- Called with actual transformed output bytes by the existing R2 IO adapter.
-- A direct RPC cannot write to R2 or refund any committed allocation.
CREATE OR REPLACE FUNCTION public.admit_image_storage_budget_internal(p_bytes bigint,p_occasion_id bigint,p_unit_id bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint;
BEGIN
 IF p_bytes IS NULL OR p_bytes<=0 THEN RAISE invalid_parameter_value USING MESSAGE='actual storage bytes required'; END IF;
 IF p_occasion_id IS NOT NULL THEN SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion_id;
 ELSE SELECT id,organization INTO un,org FROM public.units WHERE id=p_unit_id; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('image.storage',un,org),
  jsonb_build_object('unit',un,'organization',org,'global','all'),
  jsonb_build_object('image.storage.unit.bytes',p_bytes,'image.storage.organization.bytes',p_bytes,'image.storage.global.bytes',p_bytes));
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_storage_v1(p_bytes bigint,p_occasion_id bigint DEFAULT NULL,p_unit_id bigint DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR (p_occasion_id IS NULL)=(p_unit_id IS NULL)
  OR public.check_upload_permission(p_occasion_id,p_unit_id) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='image editor required'; END IF;
 RETURN public.admit_image_storage_budget_internal(p_bytes,p_occasion_id,p_unit_id);
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_storage_v1(p_bytes bigint,p_occasion_id bigint,p_unit_id bigint,p_profile text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_profile IS DISTINCT FROM 'blueprint-background' OR (p_occasion_id IS NULL)=(p_unit_id IS NULL) OR auth.uid() IS NULL
  OR NOT public.can_upload_blueprint_background(p_occasion_id,p_unit_id) THEN RAISE insufficient_privilege USING MESSAGE='blueprint image editor required'; END IF;
 RETURN public.admit_image_storage_budget_internal(p_bytes,p_occasion_id,p_unit_id);
END $$;
REVOKE ALL ON FUNCTION public.admit_image_storage_v1(bigint,bigint,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_image_storage_v1(bigint,bigint,bigint,text) TO authenticated;
REVOKE ALL ON FUNCTION public.admit_image_storage_budget_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.admit_image_storage_v1(bigint,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_image_storage_v1(bigint,bigint,bigint) TO authenticated;
