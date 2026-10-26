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
    -- This command is an internal post-delivery acknowledgement. User-facing
    -- authorization is enforced before SMTP delivery in send-app-links.
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
