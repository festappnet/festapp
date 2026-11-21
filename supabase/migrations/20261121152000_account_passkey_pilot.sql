-- Scope discoverable passkey registration and sign-in to an optional pilot account.

-- SOURCE: user_permissions/account_passkey_pilot.sql
ALTER TABLE public.account_mfa_channel_methods
  DROP CONSTRAINT IF EXISTS account_mfa_channel_methods_check1;
ALTER TABLE public.account_mfa_channel_methods
  ADD CONSTRAINT account_mfa_channel_methods_scope_check
  CHECK (method IN ('totp', 'passkey') OR registration_pilot_user IS NULL);

CREATE OR REPLACE FUNCTION public.set_passkey_pilot_user_v1(p_client_id text, p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
BEGIN
  IF NOT EXISTS (
    SELECT FROM public.external_login_clients c
    WHERE c.client_id = p_client_id AND c.provisioned AND (
      p_user IS NULL OR EXISTS (SELECT FROM public.user_info u
        WHERE u.id = p_user AND u.organization = c.organization))
  ) THEN RAISE EXCEPTION 'invalid_passkey_pilot_account'; END IF;

  INSERT INTO public.account_mfa_channel_methods (client_id, method, registration_pilot_user)
  VALUES (p_client_id, 'passkey', p_user)
  ON CONFLICT (client_id, method) DO UPDATE SET
    registration_pilot_user = excluded.registration_pilot_user,
    registration_revision = account_mfa_channel_methods.registration_revision
      + (account_mfa_channel_methods.registration_pilot_user IS DISTINCT FROM excluded.registration_pilot_user)::int,
    sign_in_revision = account_mfa_channel_methods.sign_in_revision
      + (account_mfa_channel_methods.registration_pilot_user IS DISTINCT FROM excluded.registration_pilot_user)::int;
END $$;

REVOKE ALL ON FUNCTION public.set_passkey_pilot_user_v1(text,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- A discoverable challenge is anonymous. Once GoTrue verifies it, admit
-- only the permitted session. Cancelling this UPDATE makes the broker revoke
-- the provider session without returning a handoff to the caller.
CREATE OR REPLACE FUNCTION public.enforce_passkey_pilot_session_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
BEGIN
  IF NOT EXISTS (
    SELECT FROM public.account_mfa_channel_methods m
    JOIN auth.sessions s ON s.id = NEW.session_id
    WHERE m.client_id = NEW.client_id AND m.method = 'passkey'
      AND m.sign_in_enabled AND m.sign_in_revision = NEW.sign_in_revision
      AND (m.registration_pilot_user IS NULL OR m.registration_pilot_user = s.user_id)
  ) THEN RETURN NULL; END IF;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.enforce_passkey_pilot_session_v1()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER enforce_passkey_pilot_session
  BEFORE UPDATE OF session_id ON public.account_passkey_sign_in_attempts
  FOR EACH ROW WHEN (NEW.session_id IS NOT NULL)
  EXECUTE FUNCTION public.enforce_passkey_pilot_session_v1();
