-- Authorized separate-organization provisioning, 2026-10-23.
-- Data only: no schema migration, copied users/events, provider connections or live payments.
-- Execute only on the verified canonical backend through festapp-backend-access.
\set ON_ERROR_STOP on
BEGIN;
LOCK TABLE public.organizations IN SHARE ROW EXCLUSIVE MODE;
DO $$
DECLARE
  org_id bigint;
  expected_data jsonb := '{"title":"Festapp Tickets Global","APP_NAME":"Festapp Tickets","DEFAULT_URL":"https://tickets.festap.net","DEFAULT_LANGUAGE":"en","DEFAULT_FORM_PAYMENT_METHOD":"stripe","IS_APP_SUPPORTED":false,"IS_GOOGLE_LOGIN_ENABLED":true,"IS_REGISTRATION_ENABLED":true,"IS_UNIT_CREATION_ENABLED":true}'::jsonb;
BEGIN
  IF current_database() <> 'festapp_rehearsal_20260909220601' THEN
    RAISE EXCEPTION 'Canonical database assertion failed';
  END IF;
  IF (SELECT count(*) FROM public.organizations
      WHERE title = 'Festapp Tickets Global' OR data->>'DEFAULT_URL' = 'https://tickets.festap.net') > 1 THEN
    RAISE EXCEPTION 'Ambiguous organization identity';
  END IF;
  SELECT id INTO org_id FROM public.organizations
    WHERE title = 'Festapp Tickets Global' OR data->>'DEFAULT_URL' = 'https://tickets.festap.net';
  IF org_id IS NULL THEN
    INSERT INTO public.organizations(title,data)
    VALUES ('Festapp Tickets Global',expected_data) RETURNING id INTO org_id;
  ELSIF NOT EXISTS (SELECT 1 FROM public.organizations
    WHERE id=org_id AND title='Festapp Tickets Global' AND data=expected_data) THEN
    RAISE EXCEPTION 'Existing organization differs; refusing overwrite';
  END IF;
  IF org_id = 3 THEN RAISE EXCEPTION 'Czech organization must remain separate'; END IF;
  INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode,new_payments_enabled)
    VALUES (org_id,false,false),(org_id,true,false)
    ON CONFLICT (organization_id,livemode) DO NOTHING;
  IF EXISTS (SELECT 1 FROM eshop.stripe_runtime_policy
    WHERE organization_id=org_id AND new_payments_enabled) THEN
    RAISE EXCEPTION 'Provisioning requires payments disabled';
  END IF;
END $$;
SELECT id,title,data->>'DEFAULT_URL' AS default_url,data->>'DEFAULT_LANGUAGE' AS locale,
  data->>'DEFAULT_FORM_PAYMENT_METHOD' AS default_payment
FROM public.organizations WHERE title='Festapp Tickets Global';
COMMIT;
