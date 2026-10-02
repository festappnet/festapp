-- Approved target: canonical database, organization 3, vstupenky.online.
-- Reuse the existing Google broker; enable only this tenant's two web clients.
BEGIN;
DO $$
BEGIN
  IF current_database() <> 'festapp_rehearsal_20260909220601'
     OR NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = 3
       AND data->>'APP_NAME' = 'vstupenky.online'
       AND data->>'DEFAULT_URL' = 'https://vstupenky.online') THEN
    RAISE EXCEPTION 'Google activation target mismatch';
  END IF;
END $$;
INSERT INTO public.external_login_clients
  (client_id, organization, platform, origin, redirect_uri, enabled)
VALUES
  ('3:web:https://vstupenky.online', 3, 'web', 'https://vstupenky.online', 'https://vstupenky.online/google-auth', true),
  ('3:flutter-web:https://vstupenky.online', 3, 'flutter-web', 'https://vstupenky.online', 'https://vstupenky.online/app/google-auth', true)
ON CONFLICT (client_id) DO UPDATE
SET origin = EXCLUDED.origin, redirect_uri = EXCLUDED.redirect_uri,
    enabled = EXCLUDED.enabled
WHERE external_login_clients.organization = EXCLUDED.organization
  AND external_login_clients.platform = EXCLUDED.platform;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.external_login_clients
      WHERE organization = 3 AND enabled
        AND origin = 'https://vstupenky.online'
        AND ((client_id = '3:web:https://vstupenky.online' AND platform = 'web'
              AND redirect_uri = 'https://vstupenky.online/google-auth')
          OR (client_id = '3:flutter-web:https://vstupenky.online' AND platform = 'flutter-web'
              AND redirect_uri = 'https://vstupenky.online/app/google-auth'))) <> 2 THEN
    RAISE EXCEPTION 'Google activation registry mismatch';
  END IF;
END $$;
COMMIT;
SELECT client_id, organization, platform, origin, redirect_uri, enabled
FROM public.external_login_clients WHERE organization = 3
ORDER BY client_id;
