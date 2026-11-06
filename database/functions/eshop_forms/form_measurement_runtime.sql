DROP FUNCTION IF EXISTS public.get_form_measurement_runtime_config(text,bigint,text,text);
-- Browser renewal returns minimal effective policy, never destination code/IDs.
CREATE OR REPLACE FUNCTION public.get_form_measurement_policy(p_form_link text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint:=public.resolve_form_link_internal(p_form_link);
BEGIN
 IF NOT public.can_read_public_form_measurement(fid) THEN RETURN NULL; END IF;
 RETURN public.form_measurement_runtime_internal(fid);
END $$;
REVOKE ALL ON FUNCTION public.get_form_measurement_policy(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_form_measurement_policy(text) TO anon,authenticated,service_role;

-- Only the runtime server receives Unit configuration; its credential never
-- appears in the HTML, messages, public policy, logs or parent application.
CREATE OR REPLACE FUNCTION public.get_form_measurement_runtime_config(
 p_form_link text,p_organization bigint,p_unit bigint,p_runtime_origin text,p_parent_origin text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint:=public.resolve_form_link_internal(p_form_link); result jsonb;
BEGIN
 IF NOT public.can_read_form_measurement_runtime(fid,p_organization,p_unit,p_runtime_origin,p_parent_origin) THEN
  RAISE insufficient_privilege USING MESSAGE='form measurement runtime unavailable';
 END IF;
 SELECT jsonb_build_object('organization',o.organization,'unit',u.id,'form_id',f.id,'form_link',f.link,
  'runtime_origin',r.runtime_origin,'parent_origin',p_parent_origin,'profile',r.runtime_profile,
  'ancestor_origins',r.parent_origins,'collector_origins',r.collector_origins,'policy',public.form_measurement_runtime_internal(f.id),
  'gtm_container',u.data->>'measurement_gtm_container','scripts',u.data->>'measurement_scripts') INTO result
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
 JOIN analytics.unit_runtime r ON r.unit=u.id
 WHERE f.id=fid;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_measurement_runtime_config(text,bigint,bigint,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_form_measurement_runtime_config(text,bigint,bigint,text,text) TO service_role;
