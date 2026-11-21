-- Reuse the provisioned client/tenant/callback registry independently of
-- Google enablement. Platform labels describe the registered return channel.
CREATE TABLE IF NOT EXISTS public.account_mfa_channel_methods (
  client_id text NOT NULL REFERENCES public.external_login_clients(client_id) ON DELETE CASCADE,
  method text NOT NULL CHECK (method IN ('totp', 'webauthn', 'passkey')),
  offer_enabled boolean NOT NULL DEFAULT false,
  registration_enabled boolean NOT NULL DEFAULT false,
  sign_in_enabled boolean NOT NULL DEFAULT false,
  registration_revision bigint NOT NULL DEFAULT 1,
  sign_in_revision bigint NOT NULL DEFAULT 1,
  PRIMARY KEY (client_id, method),
  CHECK (method = 'passkey' OR NOT sign_in_enabled)
);
ALTER TABLE public.account_mfa_channel_methods ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_mfa_channel_methods FROM PUBLIC, anon, authenticated, service_role;

-- Only the broker reads the policy. A resolved row describes an exact return
-- channel. It does not attest the browser, installed app, or current actor.
CREATE OR REPLACE FUNCTION public.resolve_mfa_channel_policy_v1(
  p_client_id text,
  p_organization bigint,
  p_origin text,
  p_redirect_uri text
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_policy jsonb;
BEGIN
  PERFORM public.require_service_role();
  SELECT jsonb_build_object(
    'clientId', client.client_id,
    'organization', client.organization,
    'platform', client.platform,
    'origin', client.origin,
    'redirectUri', client.redirect_uri,
    'methods', (
      SELECT jsonb_object_agg(method.key, jsonb_build_object(
        'offer', coalesce(policy.offer_enabled, false),
        'registration', coalesce(policy.registration_enabled, false),
        'signIn', coalesce(policy.sign_in_enabled, false),
        'registrationRevision', coalesce(policy.registration_revision, 0),
        'signInRevision', coalesce(policy.sign_in_revision, 0)))
      FROM (VALUES ('totp'), ('webauthn'), ('passkey')) method(key)
      LEFT JOIN public.account_mfa_channel_methods policy
        ON policy.client_id = client.client_id AND policy.method = method.key
    )
  ) INTO v_policy
  FROM public.external_login_clients client
  WHERE client.provisioned AND client.client_id = p_client_id
    AND client.organization = p_organization
    AND client.origin = p_origin AND client.redirect_uri = p_redirect_uri;
  RETURN v_policy;
END $$;

REVOKE ALL ON FUNCTION public.resolve_mfa_channel_policy_v1(text,bigint,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_mfa_channel_policy_v1(text,bigint,text,text) TO service_role;


-- Operational owner for method toggles. A restart must never revive a receipt
-- issued before a disable/re-enable sequence.
CREATE OR REPLACE FUNCTION public.set_mfa_channel_method_v1(
  p_client_id text, p_method text, p_offer boolean, p_registration boolean, p_sign_in boolean
)
RETURNS void LANGUAGE sql SECURITY INVOKER
SET search_path = public, extensions AS $$
  INSERT INTO public.account_mfa_channel_methods (
    client_id, method, offer_enabled, registration_enabled, sign_in_enabled
  ) VALUES (p_client_id, p_method, p_offer, p_registration, p_sign_in)
  ON CONFLICT (client_id, method) DO UPDATE SET
    offer_enabled = excluded.offer_enabled,
    registration_enabled = excluded.registration_enabled,
    sign_in_enabled = excluded.sign_in_enabled,
    registration_revision = account_mfa_channel_methods.registration_revision
      + (account_mfa_channel_methods.registration_enabled IS DISTINCT FROM excluded.registration_enabled)::int,
    sign_in_revision = account_mfa_channel_methods.sign_in_revision
      + (account_mfa_channel_methods.sign_in_enabled IS DISTINCT FROM excluded.sign_in_enabled)::int;
$$;

REVOKE ALL ON FUNCTION public.set_mfa_channel_method_v1(text,text,boolean,boolean,boolean)
  FROM PUBLIC, anon, authenticated, service_role;
