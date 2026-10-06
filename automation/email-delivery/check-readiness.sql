-- Read-only release gate. Run against the identity-verified canonical target.
-- Do not send canaries or mutate customer state to check producer readiness.
BEGIN READ ONLY;

DO $$
DECLARE v_health jsonb;
BEGIN
  IF NOT has_schema_privilege('service_role', 'extensions', 'USAGE') THEN
    RAISE EXCEPTION 'email_producer_permissions_missing: service_role cannot use extensions';
  END IF;
  v_health := public.get_email_delivery_health();
  IF (v_health->>'producer_access_ok')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'email_producer_permissions_missing: required producer grants or health contract';
  END IF;
  IF jsonb_typeof(v_health->'missing_account_templates') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_health->'missing_account_templates') > 0 THEN
    RAISE EXCEPTION 'email_account_templates_missing: inspect scoped missing_account_templates in delivery health';
  END IF;
END;
$$;

COMMIT;
