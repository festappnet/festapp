CREATE OR REPLACE FUNCTION public.get_effective_form_data(p_form_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    SELECT COALESCE(f.data, '{}'::jsonb) || jsonb_build_object(
        'communication_tone',
        CASE
            WHEN f.data->>'communication_tone' IN ('formal', 'informal')
                THEN f.data->>'communication_tone'
            WHEN u.data->>'communication_tone' IN ('formal', 'informal')
                THEN u.data->>'communication_tone'
            ELSE 'formal'
        END
    )
    FROM public.forms f
    JOIN public.occasions o ON o.id = f.occasion
    JOIN public.units u ON u.id = o.unit
    WHERE f.id = p_form_id;
$$;

REVOKE ALL ON FUNCTION public.get_effective_form_data(bigint)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_effective_form_data(bigint) TO service_role;
