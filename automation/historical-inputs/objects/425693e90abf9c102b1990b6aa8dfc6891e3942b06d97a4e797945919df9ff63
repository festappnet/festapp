CREATE OR REPLACE FUNCTION public.get_entity_email_templates(p_entity_type text, p_entity_id bigint)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_unit_id     bigint;
    v_org_id      bigint;

    context       jsonb;
    email_data    jsonb;

    occasion_data jsonb;
    unit_data     jsonb;
    org_data      jsonb;

    final_result  jsonb;
BEGIN
    -- 1. Resolve Hierarchy based on Entity Type
    IF p_entity_type = 'occasion' THEN
        v_occasion_id := p_entity_id;

        -- Get Unit & Org from Occasion
        SELECT unit, organization INTO v_unit_id, v_org_id
        FROM public.occasions WHERE id = v_occasion_id;

        IF v_unit_id IS NULL THEN
            RAISE EXCEPTION 'Occasion not found: %', p_entity_id;
        END IF;

    ELSIF p_entity_type = 'unit' THEN
        v_unit_id := p_entity_id;
        v_occasion_id := NULL;

        -- Get Org from Unit
        SELECT organization INTO v_org_id
        FROM public.units WHERE id = v_unit_id;

        IF v_org_id IS NULL THEN
            RAISE EXCEPTION 'Unit not found: %', p_entity_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid entity type: %', p_entity_type;
    END IF;

    -- 2. Build Context for Template Retrieval
    context := jsonb_build_object(
        'occasion', v_occasion_id,
        'unit', v_unit_id,
        'organization', v_org_id
    );

    -- 3. Retrieve Templates (using core logic)
    email_data := public.get_all_email_templates(context);

    -- 4. Retrieve Entity Details for Response

    -- Organization
    SELECT jsonb_build_object('id', id, 'title', title, 'data', data)
    INTO org_data
    FROM public.organizations WHERE id = v_org_id;

    -- Unit
    SELECT jsonb_build_object('id', id, 'title', title, 'data', COALESCE(data, '{}'::jsonb), 'email', data->>'reply_to')
    INTO unit_data
    FROM public.units WHERE id = v_unit_id;

    -- Occasion (if applicable)
    IF v_occasion_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'title', title, 'data', COALESCE(data, '{}'::jsonb), 'email', data->>'reply_to')
        INTO occasion_data
        FROM public.occasions WHERE id = v_occasion_id;
    ELSE
        occasion_data := NULL;
    END IF;

    -- 5. Build Final Result
    final_result := jsonb_build_object(
        'occasion',     occasion_data,
        'unit',         unit_data,
        'organization', org_data,
        'templates',    email_data
    );

    RETURN final_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_entity_email_templates(text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_entity_email_templates(text, bigint) TO authenticated, service_role;
