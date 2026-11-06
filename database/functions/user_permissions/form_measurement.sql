DROP FUNCTION IF EXISTS public.can_read_form_measurement_runtime(bigint,bigint,text,text);
-- Form intent uses the existing author permission; destination code is owned
-- separately by Unit managers. Rename the former private rule parameter cleanly.
DROP FUNCTION IF EXISTS public.form_measurement_write_rule(boolean,boolean);
CREATE OR REPLACE FUNCTION public.form_measurement_write_rule(p_author boolean,p_demo boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT coalesce(p_author,false) AND NOT coalesce(p_demo,true);
$$;
REVOKE ALL ON FUNCTION public.form_measurement_write_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_manage_form_measurement(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.form_measurement_write_rule(public.can_author_forms(p_occasion),public.is_demo_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_manage_form_measurement(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_form_measurement(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_public_form_measurement(p_form bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.forms f WHERE f.id=p_form AND f.is_open AND f.link IS NOT NULL
  AND NOT public.is_demo_occasion(f.occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_public_form_measurement(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_form_measurement_runtime(p_form bigint,p_organization bigint,p_unit bigint,p_runtime_origin text,p_parent_origin text)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT auth.role()='service_role' AND public.can_read_public_form_measurement(p_form) AND
  EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
   JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
   JOIN analytics.unit_runtime r ON r.unit=u.id
   WHERE f.id=p_form AND o.organization=p_organization AND u.id=p_unit AND r.runtime_origin=p_runtime_origin
   AND p_parent_origin=ANY(r.parent_origins)
   AND public.form_measurement_status_internal(f.id)->'eligible'='true'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.can_read_form_measurement_runtime(bigint,bigint,bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
