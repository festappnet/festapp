-- The public broker permits ordinary verification only for an existing
-- verified factor owned by the actor. GoTrue validates the actual challenge.
CREATE OR REPLACE FUNCTION public.can_use_existing_mfa_factor_v1(p_factor uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  IF public.get_account_assurance_v1() NOT IN ('allowed', 'mfa_required', 'proof_required') THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT FROM auth.mfa_factors
    WHERE id = p_factor AND user_id = auth.uid() AND status = 'verified'
      AND factor_type IN ('totp', 'phone', 'webauthn')
  );
END $$;

-- Preserve ordinary password/account updates for accounts without an everyday
-- factor. An enrolled account requires fresh account security assurance.
CREATE OR REPLACE FUNCTION public.can_update_public_auth_account_v1()
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  IF public.get_account_assurance_v1() IS DISTINCT FROM 'allowed' THEN
    RETURN false;
  END IF;
  IF EXISTS (SELECT FROM auth.mfa_factors WHERE user_id = auth.uid()
    AND status = 'verified' AND factor_type IN ('totp', 'phone', 'webauthn')) THEN
    RETURN public.get_account_assurance_v1(NULL, true) = 'allowed';
  END IF;
  RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.can_use_existing_mfa_factor_v1(uuid),
  public.can_update_public_auth_account_v1() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_use_existing_mfa_factor_v1(uuid),
  public.can_update_public_auth_account_v1() TO authenticated;
