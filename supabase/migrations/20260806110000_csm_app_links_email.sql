CREATE OR REPLACE FUNCTION public.mark_app_links_sent(
    p_occasion_id bigint,
    p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    -- This command is an internal post-delivery acknowledgement. User-facing
    -- authorization is enforced before SMTP delivery in send-app-links.
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'Service role required'
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

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion user not found');
    END IF;

    RETURN jsonb_build_object('code', 200, 'message', 'Application links marked as sent');
END;
$$;

REVOKE ALL ON FUNCTION public.mark_app_links_sent(bigint, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_app_links_sent(bigint, uuid) TO service_role;

INSERT INTO public.email_templates(html, subject, organization, code, title)
SELECT
  '{{appLinks}}',
  'Aplikace CSM Ostrava',
  9,
  'APP_LINKS',
  'Odkazy na aplikace'
WHERE EXISTS (SELECT 1 FROM public.organizations WHERE id = 9)
  AND NOT EXISTS (
    SELECT 1
    FROM public.email_templates
    WHERE organization = 9
      AND unit IS NULL
      AND occasion IS NULL
      AND code = 'APP_LINKS'
  );
