-- Public metadata only. Route kind keeps form and occasion namespaces distinct.
-- Existing one-argument callers retain their form-first resolution contract.
CREATE OR REPLACE FUNCTION public.get_occasion_seo_data(p_link_slug text, p_route_type text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_occasion_id bigint; v_form public.forms%ROWTYPE; v_result json;
BEGIN
    IF p_route_type NOT IN ('form', 'event') OR p_route_type IS NULL THEN
        RAISE invalid_parameter_value USING MESSAGE = 'Invalid public SEO route';
    END IF;
    IF p_route_type = 'form' THEN
        SELECT * INTO v_form FROM public.forms
        WHERE id = public.resolve_form_link_internal(p_link_slug);
        v_occasion_id := v_form.occasion;
    ELSE
        v_occasion_id := public.resolve_occasion_link_internal(p_link_slug);
    END IF;
    SELECT json_build_object(
        'title', o.title, 'description', o.description,
        'form_title', v_form.title, 'form_description', v_form.header,
        'form_link', v_form.link, 'occasion_link', o.link,
        'start_time', o.start_time, 'end_time', o.end_time,
        'image', o.data->>'image', 'org_title', org.title, 'unit_title', u.title
    ) INTO v_result
    FROM public.occasions o
    JOIN public.organizations org ON org.id = o.organization
    LEFT JOIN public.units u ON u.id = o.unit
    WHERE o.id = v_occasion_id;
    RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_seo_data(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_occasion_seo_data(text,text) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_occasion_seo_data(p_link_slug text)
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path = public, extensions AS $$
    SELECT coalesce(public.get_occasion_seo_data(p_link_slug, 'form'), public.get_occasion_seo_data(p_link_slug, 'event'));
$$;
REVOKE ALL ON FUNCTION public.get_occasion_seo_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_occasion_seo_data(text) TO anon, authenticated, service_role;
