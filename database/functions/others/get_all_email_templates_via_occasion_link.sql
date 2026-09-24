CREATE OR REPLACE FUNCTION public.get_all_email_templates_via_occasion_link(occasion_link text)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
BEGIN
    -- Canonical merges may contain the same legacy link in multiple tenants.
    SELECT o.id
    INTO v_occasion_id
    FROM public.occasions o
    WHERE o.link = occasion_link
      AND o.organization = (
        SELECT ui.organization
        FROM public.user_info ui
        WHERE ui.id = auth.uid()
      );

    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion not found for link: %', occasion_link;
    END IF;

    -- Call Unified Function
    RETURN public.get_entity_email_templates('occasion', v_occasion_id);
END;
$$;
