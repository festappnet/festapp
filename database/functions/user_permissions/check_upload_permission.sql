CREATE OR REPLACE FUNCTION public.check_upload_permission(
    p_occasion_id bigint DEFAULT NULL,
    p_unit_id bigint DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;

    IF p_unit_id IS NOT NULL THEN
        RETURN public.can_upload_unit_media(p_unit_id);
    ELSIF p_occasion_id IS NOT NULL THEN
        RETURN public.can_upload_occasion_media(p_occasion_id);
    END IF;

    RETURN false;
END;
$$;
