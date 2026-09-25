-- Keep the legacy helper on the same permission-checked creation path as the
-- client-sync command. The internal creator omits communication_tone, so the
-- form follows its unit until an explicit override is saved.
CREATE OR REPLACE FUNCTION public.create_form(
    p_occasion_id bigint,
    p_link text,
    p_title text
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT public.create_form_internal_v1(p_occasion_id, p_link, p_title);
$$;

REVOKE ALL ON FUNCTION public.create_form(bigint, text, text)
FROM PUBLIC, anon, authenticated;
