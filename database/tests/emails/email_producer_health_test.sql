BEGIN;

DO $$
DECLARE v_health jsonb;
BEGIN
  REVOKE USAGE ON SCHEMA extensions FROM service_role;
  v_health := public.get_email_delivery_health();
  IF (v_health->>'producer_access_ok')::boolean IS DISTINCT FROM false
    OR NOT (v_health->'alerts' ? 'producer_permissions_missing') THEN
    RAISE EXCEPTION 'Health must detect producer schema access failure';
  END IF;
  GRANT USAGE ON SCHEMA extensions TO service_role;
  v_health := public.get_email_delivery_health();
  IF (v_health->>'producer_access_ok')::boolean IS DISTINCT FROM true
    OR v_health->'alerts' ? 'producer_permissions_missing' THEN
    RAISE EXCEPTION 'Health must clear the repaired producer access alert';
  END IF;
  REVOKE EXECUTE ON FUNCTION public.enqueue_account_email(
    text, jsonb, jsonb, text, jsonb, text, text, text, timestamptz
  ) FROM service_role;
  v_health := public.get_email_delivery_health();
  IF (v_health->>'producer_access_ok')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Health must also detect a missing account producer grant';
  END IF;
  IF has_function_privilege('anon', 'public.get_email_delivery_health()', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.get_email_delivery_health()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Email health must remain internal';
  END IF;
END;
$$;

ROLLBACK;
