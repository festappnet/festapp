-- Public page metadata: canonical saved identities and server/client parity.
-- Definition-only; canonical sources below. Apply backend before the edge/client release.
BEGIN;

-- Source: database/functions/others/get_occasion_seo_data.sql
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


-- Source: database/functions/eshop_forms/get_form_by_link.sql
CREATE OR REPLACE FUNCTION public.get_form_bundle_internal(p_form_id bigint,p_allow_closed boolean DEFAULT false)
RETURNS JSON LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
    allData JSON;
    generated_secret UUID := gen_random_uuid();
    form_exists BOOLEAN;
    is_editor_view BOOLEAN := false;
    occ_id BIGINT;
BEGIN
    -- Check if the form exists
    SELECT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id
    ) INTO form_exists;

    IF NOT form_exists THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Form does not exist.'
        );
    END IF;

    SELECT occasion INTO occ_id FROM public.forms WHERE id = p_form_id;
    is_editor_view := public.get_is_editor_order_view_on_occasion(occ_id);


    IF NOT p_allow_closed AND NOT is_editor_view AND NOT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id AND is_open = true
    ) THEN
        -- If the form is closed, retrieve only the 'header_off' message
        SELECT jsonb_build_object(
            'code', 400,
            'data', jsonb_build_object(
                'organizationIdentity', (SELECT CASE WHEN o.organization=u.organization THEN public.get_verified_unit_identity_internal(u.id) END FROM public.occasions o JOIN public.units u ON u.id=o.unit WHERE o.id=f.occasion),
                'header_off', f.header_off,
                'seo', public.get_occasion_seo_data(f.link, 'form'),
                'is_open', f.is_open
            )
        )
        INTO allData
        FROM public.forms f
        WHERE f.id = p_form_id;

        RETURN allData;
    END IF;

    -- If the form is open, retrieve the full form data including dynamic product availability
    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'organizationIdentity', CASE WHEN o.organization=(SELECT organization FROM public.units WHERE id=o.unit) THEN public.get_verified_unit_identity_internal(o.unit) END,
            'payments',public.form_payment_availability_internal(f.id),
            'capacity', public.get_form_capacity_snapshot_internal(f.id),
            'registrationMode',public.get_form_registration_mode_internal(f.id),
            'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'id', f.id,
            'link', f.link,
            'key', f.key,
            'created_at', f.created_at,
            'data', public.get_effective_form_data(f.id),
            'type', f.type,
            'title', f.title,
            'seo', public.get_occasion_seo_data(f.link, 'form'),
            'is_open', f.is_open,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', jsonb_build_object(
                'id', o.id,
                'features', o.features,
                'start_time', o.start_time
            ),
            'blueprint', CASE WHEN EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
                AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)'))
                THEN f.blueprint END,
            'deadline_duration_seconds', f.deadline_duration_seconds,
            'account_number', ba.account_number,
            'secret', generated_secret,
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'data', p.data,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum,
                                                    'is_dynamically_available', is_product_dynamically_available(p.id)
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                              AND NOT p.is_hidden
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                WHERE ff.form = f.id AND ff.is_hidden = false
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    LEFT JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    RETURN allData;
END;
$$;

REVOKE ALL ON FUNCTION public.get_form_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_form_by_link(form_link text)
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path=public,extensions AS $$
 SELECT public.get_form_bundle_internal(public.resolve_form_link_internal(form_link),false);
$$;


NOTIFY pgrst, 'reload schema';
COMMIT;
