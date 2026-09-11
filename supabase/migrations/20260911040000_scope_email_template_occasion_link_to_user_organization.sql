-- Canonical merges can contain the same legacy occasion link in more than one
-- organization. Resolve e-mail template reads inside the authenticated tenant.
CREATE OR REPLACE FUNCTION public.get_all_email_templates_via_occasion_link(occasion_link text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
BEGIN
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

    RETURN public.get_entity_email_templates('occasion', v_occasion_id);
END;
$$;
