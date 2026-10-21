CREATE OR REPLACE FUNCTION public.get_can_manage_occasion_users(
    p_occasion_id bigint
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_unit_id bigint;
BEGIN
    SELECT o.unit
      INTO v_unit_id
      FROM public.occasions o
     WHERE o.id = p_occasion_id;

    IF NOT FOUND OR auth.uid() IS NULL THEN
        RETURN false;
    END IF;

    RETURN public.get_is_manager_on_occasion(p_occasion_id)
        OR public.get_is_admin_on_occasion(p_occasion_id)
        OR (
            v_unit_id IS NOT NULL
            AND public.get_is_editor_on_unit(v_unit_id)
        );
END;
$$;

REVOKE ALL ON FUNCTION public.get_can_manage_occasion_users(bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_can_manage_occasion_users(bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_app_links_sent(
    p_occasion_id bigint,
    p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_already_sent boolean;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'Service role required'
        );
    END IF;

    SELECT COALESCE(ou.data->>'app_links_sent' = 'true', false)
      INTO v_already_sent
      FROM public.occasion_users ou
     WHERE ou.occasion = p_occasion_id
       AND ou."user" = p_user_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion user not found');
    END IF;

    IF v_already_sent THEN
        RETURN jsonb_build_object(
            'code', 200,
            'message', 'Application links already marked as sent'
        );
    END IF;

    UPDATE public.occasion_users
       SET data = jsonb_set(
           COALESCE(data, '{}'::jsonb),
           '{app_links_sent}',
           'true'::jsonb,
           true
       )
     WHERE occasion = p_occasion_id
       AND "user" = p_user_id;

    INSERT INTO public.client_aggregate_versions
        (aggregate_type, scope_type, scope_id, aggregate_id, version)
    VALUES
        ('occasion_user', 'occasion', p_occasion_id, p_user_id::text, 0)
    ON CONFLICT DO NOTHING;

    UPDATE public.client_aggregate_versions
       SET version = version + 1,
           updated_at = clock_timestamp()
     WHERE aggregate_type = 'occasion_user'
       AND scope_type = 'occasion'
       AND scope_id = p_occasion_id
       AND aggregate_id = p_user_id::text;

    RETURN jsonb_build_object('code', 200, 'message', 'Application links marked as sent');
END;
$$;

REVOKE ALL ON FUNCTION public.mark_app_links_sent(bigint, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_app_links_sent(bigint, uuid) TO service_role;

-- Invalidate any Users-grid snapshots loaded before this migration for rows
-- that were already marked by the initial deployment.
INSERT INTO public.client_aggregate_versions
    (aggregate_type, scope_type, scope_id, aggregate_id, version)
SELECT
    'occasion_user',
    'occasion',
    ou.occasion,
    ou."user"::text,
    1
FROM public.occasion_users ou
WHERE ou.data->>'app_links_sent' = 'true'
ON CONFLICT (aggregate_type, scope_type, scope_id, aggregate_id)
DO UPDATE SET
    version = public.client_aggregate_versions.version + 1,
    updated_at = clock_timestamp();
