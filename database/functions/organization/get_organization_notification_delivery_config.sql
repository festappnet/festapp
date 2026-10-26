CREATE OR REPLACE FUNCTION public.get_organization_notification_delivery_config(
  p_organization_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM public.require_service_role();

  SELECT jsonb_build_object(
    'onesignal_app_id', o.data->>'ONESIGNAL_APP_ID',
    'onesignal_rest_api_key', s.onesignal_rest_api_key,
    'default_url', o.data->>'DEFAULT_URL'
  )
  INTO v_result
  FROM public.organizations o
  JOIN public.organization_notification_secrets s
    ON s.organization = o.id
  WHERE o.id = p_organization_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_organization_notification_delivery_config(bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_organization_notification_delivery_config(bigint)
  TO service_role;
