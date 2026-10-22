-- Google OIDC broker, disabled until explicit client provisioning.

-- Source: database/functions/users/existing_user_session.sql
-- Shared, distributed serialization for internal GoTrue recovery minting.
CREATE OR REPLACE FUNCTION public.format_auth_email(p_organization bigint, p_sign_in_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE v_email text := lower(btrim(p_sign_in_email)); v_result text;
BEGIN
  IF p_organization IS NULL OR p_organization <= 0 OR v_email IS NULL
     OR v_email = '' OR position('@' IN v_email) <= 1 THEN
    RAISE EXCEPTION 'INVALID_USER_EMAIL';
  END IF;
  v_result := p_organization::text || '+' || v_email;
  IF octet_length(v_result) > 254 THEN RAISE EXCEPTION 'INVALID_USER_EMAIL'; END IF;
  RETURN v_result;
END $$;

CREATE TABLE IF NOT EXISTS public.existing_user_session_leases (
  user_id uuid PRIMARY KEY REFERENCES public.user_info(id) ON DELETE CASCADE,
  owner uuid NOT NULL,
  expires_at timestamptz NOT NULL
);
ALTER TABLE public.existing_user_session_leases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.existing_user_session_leases FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.existing_user_session_leases TO service_role;

CREATE OR REPLACE FUNCTION public.resolve_existing_user_session_v1(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_profile public.user_info%rowtype; v_auth auth.users%rowtype;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_profile FROM public.user_info WHERE id=p_user;
  SELECT * INTO v_auth FROM auth.users WHERE id=p_user;
  IF v_profile.id IS NULL OR v_auth.id IS NULL OR v_auth.deleted_at IS NOT NULL
    OR v_auth.banned_until > clock_timestamp()
    OR v_auth.email IS DISTINCT FROM public.format_auth_email(v_profile.organization,v_profile.email_readonly) THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('userId',v_auth.id,'authEmail',v_auth.email,'organization',v_profile.organization,'requiresMfa',EXISTS(SELECT 1 FROM auth.mfa_factors WHERE user_id=p_user AND status='verified'));
END $$;

CREATE OR REPLACE FUNCTION public.acquire_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_target jsonb; v_acquired uuid;
BEGIN
  PERFORM public.require_service_role();
  IF p_owner IS NULL THEN RAISE EXCEPTION 'invalid_lease_owner'; END IF;
  v_target := public.resolve_existing_user_session_v1(p_user);
  IF v_target IS NULL THEN RETURN NULL; END IF;
  INSERT INTO public.existing_user_session_leases(user_id,owner,expires_at)
    VALUES(p_user,p_owner,clock_timestamp()+interval '120 seconds')
  ON CONFLICT(user_id) DO UPDATE SET owner=excluded.owner,expires_at=excluded.expires_at
    WHERE existing_user_session_leases.expires_at <= clock_timestamp()
  RETURNING owner INTO v_acquired;
  IF v_acquired IS NULL THEN RETURN NULL; END IF;
  RETURN v_target;
END $$;

CREATE OR REPLACE FUNCTION public.check_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF NOT EXISTS(SELECT 1 FROM public.existing_user_session_leases
      WHERE user_id=p_user AND owner=p_owner AND expires_at>clock_timestamp()) THEN RETURN NULL; END IF;
  RETURN public.resolve_existing_user_session_v1(p_user);
END $$;

CREATE OR REPLACE FUNCTION public.release_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM public.existing_user_session_leases WHERE user_id=p_user AND owner=p_owner;
END $$;

REVOKE ALL ON FUNCTION public.resolve_existing_user_session_v1(uuid),
  public.acquire_existing_user_session_lease_v1(uuid,uuid),
  public.check_existing_user_session_lease_v1(uuid,uuid),
  public.release_existing_user_session_lease_v1(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_existing_user_session_v1(uuid),
  public.acquire_existing_user_session_lease_v1(uuid,uuid),
  public.check_existing_user_session_lease_v1(uuid,uuid),
  public.release_existing_user_session_lease_v1(uuid,uuid) TO service_role;


-- Source: database/functions/users/create_user_in_organization_with_data_pure.sql
CREATE OR REPLACE FUNCTION public.create_user_in_organization_with_data_pure(
    org bigint,
    email text,
    email_delivery text,
    password text,
    data jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    usr uuid;
    encrypted_pw text;
    user_meta_data jsonb := '{}';
    _key   text;
    _value text;
    trimmed_data jsonb := '{}';
    original_email text;
    normalized_delivery_email text;
BEGIN
    original_email := lower(trim(email));
    normalized_delivery_email := COALESCE(
        NULLIF(lower(trim(email_delivery)), ''), original_email
    );

    IF original_email IS NULL OR original_email = ''
       OR normalized_delivery_email IS NULL OR normalized_delivery_email = ''
       OR position('@' IN original_email) <= 1
       OR position('@' IN normalized_delivery_email) <= 1 THEN
        RAISE EXCEPTION 'INVALID_USER_EMAIL';
    END IF;

    -- All application writers serialize identity creation per organization.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('user-sign-in-email:' || org::text, 0)
    );

    IF EXISTS (
        SELECT 1 FROM public.user_info ui
         WHERE ui.organization = org
           AND lower(btrim(ui.email_readonly)) = original_email
    ) THEN
        RAISE EXCEPTION 'SIGN_IN_EMAIL_ALREADY_EXISTS';
    END IF;

    -- Add organization prefix to the email for auth tables
    email := public.format_auth_email(org, original_email);

    -- Trim all values in the data JSONB object and build a new trimmed_data JSONB object
    FOR _key, _value IN
        SELECT key, value FROM jsonb_each_text(data)
    LOOP
        IF _value IS NOT NULL THEN
            trimmed_data := jsonb_set(trimmed_data, array[_key], to_jsonb(trim(_value)), true);
        ELSE
            trimmed_data := jsonb_set(trimmed_data, array[_key], 'null'::jsonb, true);
        END IF;
    END LOOP;

    usr := gen_random_uuid();
    encrypted_pw := crypt(password, gen_salt('bf'));

    -- Insert into auth.users with the email prefixed with organization
    INSERT INTO auth.users
      (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
    VALUES
      ('00000000-0000-0000-0000-000000000000', usr, 'authenticated', 'authenticated', email, encrypted_pw, now(), NULL, NULL,
      '{"provider":"email","providers":["email"]}', user_meta_data, now(), now(), '', '', '', '');

    -- Insert into auth.identities with the email prefixed with organization
    INSERT INTO auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES
      (gen_random_uuid(), usr, usr, format('{"sub":"%s","email":"%s"}', usr::text, email)::jsonb, 'email', NULL, now(), now());

    -- The account email is canonical; store only a distinct delivery override.
    INSERT INTO user_info (
      id, email_readonly, email_delivery, name, surname, sex, phone, birth_date, data,
      organization
    )
    VALUES (
      usr,
      original_email,
      NULLIF(normalized_delivery_email, original_email),
      COALESCE(trimmed_data->>'name', ''),
      COALESCE(trimmed_data->>'surname', ''),
      COALESCE(trimmed_data->>'sex', ''),
      trimmed_data->>'phone',
      NULLIF(trimmed_data->>'birthDate', '')::date,
      trimmed_data,
      org
    );

    RETURN usr;
END;
$$;

-- Compatibility boundary for released callers. New code supplies the delivery
-- address explicitly; ordinary registrations use the sign-in email for both.
CREATE OR REPLACE FUNCTION public.create_user_in_organization_with_data_pure(
    org bigint,
    email text,
    password text,
    data jsonb
)
RETURNS uuid
LANGUAGE sql
SET search_path = public, extensions
AS $$
    SELECT public.create_user_in_organization_with_data_pure(
        org, email, email, password, data
    );
$$;


-- Source: database/functions/users/initialize_registration_unit_v1.sql
-- Internal initializer shared by password and externally verified registration.
CREATE OR REPLACE FUNCTION public.initialize_registration_unit_v1(p_user uuid,p_organization bigint,p_raw_email text,p_title text)
RETURNS bigint LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_unit bigint;
BEGIN
  INSERT INTO public.units(title,organization,data) VALUES(p_title,p_organization,jsonb_build_object('reply_to',lower(btrim(p_raw_email)),'timezone','Europe/Prague')) RETURNING id INTO v_unit;
  INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) VALUES(v_unit,p_user,true,true,true);
  RETURN v_unit;
END $$;
REVOKE ALL ON FUNCTION public.initialize_registration_unit_v1(uuid,bigint,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_registration_unit_v1(uuid,bigint,text,text) TO service_role;


-- Source: database/functions/users/create_user_from_registration.sql
CREATE OR REPLACE FUNCTION public.create_user_from_registration(
    org bigint,
    email text,
    password text,
    data jsonb,
    unit_title text DEFAULT 'Moje akce'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    is_registration_enabled BOOLEAN;
    new_user_id uuid;
    v_new_unit_id bigint;
BEGIN
    -- Retrieve IS_REGISTRATION_ENABLED value from organizations.data JSON
    SELECT (organizations.data->>'IS_REGISTRATION_ENABLED')::boolean
      INTO is_registration_enabled
    FROM organizations
    WHERE id = org;

    -- CHECK: If registration is enabled OR if the caller is a manager/editor
    IF is_registration_enabled IS DISTINCT FROM true AND NOT (
           get_is_manager_on_any_occasion()
           OR EXISTS (
               SELECT 1
               FROM occasions o
               WHERE o.organization = org
               AND get_is_editor_on_unit(o.unit)
           )
       ) THEN
        RETURN jsonb_build_object('code', 403, 'error', 'Registration is disabled for this organization');
    END IF;

    -- Call the PURE function to create the user
    new_user_id := create_user_in_organization_with_data_pure(org, email, password, data);

    PERFORM public.initialize_registration_unit_v1(new_user_id, org, email, unit_title);

    RETURN jsonb_build_object('code', 200, 'id', new_user_id);
END;
$$;


-- Source: database/functions/users/google_auth.sql
-- Capabilities are provisioned by an operator for one approved tenant/client.
-- Empty table = unavailable. Origins and redirects are exact, not suffix matches.
CREATE TABLE IF NOT EXISTS public.external_login_clients (
  client_id text PRIMARY KEY,
  organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  platform text NOT NULL CHECK(platform IN ('web','flutter-web','android','ios')),
  origin text NOT NULL CHECK(origin ~ '^https://[^/?#]+$'),
  redirect_uri text NOT NULL CHECK(redirect_uri ~ '^https://[^?#]+$'),
  enabled boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX IF NOT EXISTS user_info_external_login_org_key ON public.user_info(id,organization);
CREATE TABLE IF NOT EXISTS public.external_login_identities (
  organization bigint NOT NULL,
  user_id uuid NOT NULL,
  provider text NOT NULL DEFAULT 'google' CHECK(provider='google'),
  issuer text NOT NULL CHECK(issuer='https://accounts.google.com'),
  subject text NOT NULL CHECK(length(subject) BETWEEN 1 AND 255),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(organization,provider,issuer,subject),
  UNIQUE(organization,user_id,provider),
  FOREIGN KEY(user_id,organization) REFERENCES public.user_info(id,organization) ON DELETE CASCADE,
  FOREIGN KEY(user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS public.external_login_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id text NOT NULL REFERENCES public.external_login_clients(client_id) ON DELETE CASCADE,
  organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  intent text NOT NULL DEFAULT 'login' CHECK(intent IN ('login','unlink')),
  status text NOT NULL CHECK(status IN ('created','bootstrapped','provider_verified','awaiting_account_proof','awaiting_profile','awaiting_mfa','ready','issuing','consumed','failed')),
  challenge text NOT NULL CHECK(length(challenge)=43),
  state_hash text NOT NULL UNIQUE,
  nonce_hash text NOT NULL,
  bootstrap_hash text,
  browser_hash text,
  verifier_encrypted text,
  expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '10 minutes',
  handoff_hash text UNIQUE,
  handoff_expires_at timestamptz,
  continuation_hash text,
  issuer text,
  subject text,
  email text,
  proposed_name text,
  mailbox_verified boolean NOT NULL DEFAULT false,
  mailbox_hash text,
  mailbox_tries integer NOT NULL DEFAULT 0,
  mfa_session_encrypted text,
  mfa_user uuid REFERENCES public.user_info(id) ON DELETE CASCADE,
  target_user uuid REFERENCES public.user_info(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.external_login_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.external_login_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.external_login_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.external_login_clients,public.external_login_identities,public.external_login_attempts FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.external_login_clients,public.external_login_identities,public.external_login_attempts TO service_role;

CREATE TABLE IF NOT EXISTS public.external_login_rate_limits (
  key_hash text PRIMARY KEY, window_start timestamptz NOT NULL, hits integer NOT NULL
);
ALTER TABLE public.external_login_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.external_login_rate_limits FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.external_login_rate_limits TO service_role;
CREATE OR REPLACE FUNCTION public.google_auth_rate_limit_v1(p_key text,p_limit integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_hits integer;
BEGIN
  PERFORM public.require_service_role();
  IF p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_limit'; END IF;
  INSERT INTO public.external_login_rate_limits VALUES(p_key,clock_timestamp(),1)
  ON CONFLICT(key_hash) DO UPDATE SET
    hits=CASE WHEN external_login_rate_limits.window_start < clock_timestamp()-interval '1 minute' THEN 1 ELSE external_login_rate_limits.hits+1 END,
    window_start=CASE WHEN external_login_rate_limits.window_start < clock_timestamp()-interval '1 minute' THEN clock_timestamp() ELSE external_login_rate_limits.window_start END
  RETURNING hits INTO v_hits;
  RETURN v_hits<=p_limit;
END $$;

CREATE OR REPLACE FUNCTION public.google_auth_resolve_account_v1(p_organization bigint,p_raw_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_users uuid[];
BEGIN
  PERFORM public.require_service_role();
  SELECT array_agg(id) INTO v_users FROM public.user_info
  WHERE organization=p_organization AND lower(btrim(email_readonly))=lower(btrim(p_raw_email));
  IF cardinality(v_users) IS DISTINCT FROM 1 THEN RETURN NULL; END IF;
  RETURN public.resolve_existing_user_session_v1(v_users[1]);
END $$;

-- Each transition takes an attempt row lock. Payload is trusted server data:
-- this RPC is never callable by anon or authenticated clients.
CREATE OR REPLACE FUNCTION public.google_auth_transition_v1(p_operation text,p_attempt uuid,p_secret_hash text,p_payload jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a public.external_login_attempts%rowtype; c public.external_login_clients%rowtype;
  v_user uuid; v_existing uuid; v_target jsonb; v_status text; v_signup boolean;
BEGIN
  PERFORM public.require_service_role();
  IF p_operation='start' THEN
    SELECT * INTO c FROM public.external_login_clients WHERE client_id=p_payload->>'clientId' AND enabled;
    IF c.client_id IS NULL OR c.organization IS DISTINCT FROM (p_payload->>'organization')::bigint
      OR c.origin IS DISTINCT FROM p_payload->>'origin' THEN RAISE EXCEPTION 'provider_unavailable'; END IF;
    INSERT INTO public.external_login_attempts(id,client_id,organization,intent,status,challenge,state_hash,nonce_hash,bootstrap_hash,verifier_encrypted)
    VALUES(p_attempt,c.client_id,c.organization,coalesce(p_payload->>'intent','login'),'created',p_payload->>'challenge',p_payload->>'stateHash',p_payload->>'nonceHash',p_secret_hash,p_payload->>'verifierEncrypted') RETURNING * INTO a;
    RETURN to_jsonb(a)||jsonb_build_object('redirectUri',c.redirect_uri,'origin',c.origin);
  END IF;
  SELECT * INTO a FROM public.external_login_attempts WHERE id=p_attempt FOR UPDATE;
  IF a.id IS NULL OR a.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'attempt_expired'; END IF;
  SELECT * INTO c FROM public.external_login_clients WHERE client_id=a.client_id AND enabled;
  IF c.client_id IS NULL THEN RAISE EXCEPTION 'provider_unavailable'; END IF;
  IF p_operation='bootstrap' THEN
    IF a.status<>'created' OR a.bootstrap_hash IS DISTINCT FROM p_secret_hash THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
    UPDATE public.external_login_attempts SET status='bootstrapped',bootstrap_hash=NULL,browser_hash=p_payload->>'browserHash' WHERE id=a.id RETURNING * INTO a;
  ELSIF p_operation='provider' THEN
    IF a.status<>'bootstrapped' OR a.state_hash IS DISTINCT FROM p_secret_hash
       OR a.browser_hash IS DISTINCT FROM p_payload->>'browserHash' THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
    IF p_payload->>'issuer' <> 'https://accounts.google.com' OR coalesce(p_payload->>'subject','')='' THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
    UPDATE public.external_login_attempts SET status='provider_verified',issuer=p_payload->>'issuer',subject=p_payload->>'subject',
      email=lower(btrim(p_payload->>'email')),proposed_name=p_payload->>'name',mailbox_verified=(p_payload->>'mailboxVerified')::boolean,
      handoff_hash=p_payload->>'handoffHash',handoff_expires_at=clock_timestamp()+interval '60 seconds',verifier_encrypted=NULL
    WHERE id=a.id RETURNING * INTO a;
  ELSIF p_operation='claim' THEN
    IF a.status<>'provider_verified' OR a.handoff_hash IS DISTINCT FROM p_secret_hash
      OR a.handoff_expires_at<=clock_timestamp() OR a.challenge IS DISTINCT FROM p_payload->>'challenge' THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
    SELECT user_id INTO v_user FROM public.external_login_identities WHERE organization=a.organization AND issuer=a.issuer AND subject=a.subject;
    IF v_user IS NOT NULL THEN
      IF public.resolve_existing_user_session_v1(v_user) IS NULL THEN RAISE EXCEPTION 'account_identity_inconsistent'; END IF;
      v_status := CASE WHEN a.intent='unlink' OR (public.resolve_existing_user_session_v1(v_user)->>'requiresMfa')::boolean IS TRUE THEN 'awaiting_account_proof' ELSE 'ready' END;
    ELSE
      IF a.intent='unlink' THEN RAISE EXCEPTION 'account_proof_failed'; END IF;
      SELECT (data->>'IS_REGISTRATION_ENABLED')::boolean IS TRUE INTO v_signup FROM public.organizations WHERE id=a.organization;
      IF EXISTS(SELECT 1 FROM public.user_info WHERE organization=a.organization AND lower(btrim(email_readonly))=a.email) OR v_signup IS DISTINCT FROM true THEN v_status := 'awaiting_account_proof';
      ELSE v_status := 'awaiting_profile'; END IF;
    END IF;
    UPDATE public.external_login_attempts SET status=v_status,target_user=v_user,handoff_hash=NULL,continuation_hash=p_payload->>'continuationHash'
    WHERE id=a.id RETURNING * INTO a;
  ELSE
    IF a.continuation_hash IS DISTINCT FROM p_secret_hash OR a.challenge IS DISTINCT FROM p_payload->>'challenge' THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
    IF p_operation='mfa_begin' THEN
      IF a.status NOT IN ('awaiting_account_proof','awaiting_profile') THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
      v_user := (p_payload->>'provenUser')::uuid;
      v_target := public.resolve_existing_user_session_v1(v_user);
      IF v_target IS NULL OR (v_target->>'organization')::bigint<>a.organization
        OR (a.target_user IS NOT NULL AND a.target_user<>v_user) THEN RAISE EXCEPTION 'account_proof_failed'; END IF;
      UPDATE public.external_login_attempts SET status='awaiting_mfa',mfa_user=v_user,
        mfa_session_encrypted=p_payload->>'sessionEncrypted',continuation_hash=p_payload->>'continuationHash' WHERE id=a.id RETURNING * INTO a;
    ELSIF p_operation='mfa_proven' THEN
      IF a.status<>'awaiting_mfa' OR a.mfa_user IS DISTINCT FROM (p_payload->>'provenUser')::uuid THEN RAISE EXCEPTION 'account_proof_failed'; END IF;
      UPDATE public.external_login_attempts SET status='awaiting_account_proof',mfa_session_encrypted=NULL WHERE id=a.id RETURNING * INTO a;
    ELSIF p_operation='mailbox_send' THEN
      IF a.status<>'awaiting_profile' OR a.mailbox_verified OR a.mailbox_hash IS NOT NULL THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
      UPDATE public.external_login_attempts SET mailbox_hash=p_payload->>'mailboxHash' WHERE id=a.id RETURNING * INTO a;
    ELSIF p_operation='mailbox_verify' THEN
      IF a.status<>'awaiting_profile' OR a.mailbox_tries>=5 THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
      UPDATE public.external_login_attempts SET mailbox_tries=mailbox_tries+1,mailbox_verified=(mailbox_hash IS NOT NULL AND mailbox_hash=p_payload->>'mailboxHash'),
        continuation_hash=p_payload->>'continuationHash' WHERE id=a.id RETURNING * INTO a;
    ELSIF p_operation='unlink' THEN
      IF a.intent<>'unlink' OR a.status<>'awaiting_account_proof' OR a.target_user IS DISTINCT FROM (p_payload->>'provenUser')::uuid
        OR public.resolve_existing_user_session_v1(a.target_user) IS NULL THEN RAISE EXCEPTION 'account_proof_failed'; END IF;
      DELETE FROM public.external_login_identities WHERE organization=a.organization AND user_id=a.target_user AND issuer=a.issuer AND subject=a.subject;
      IF NOT FOUND THEN RAISE EXCEPTION 'identity_already_linked'; END IF;
      DELETE FROM public.external_login_attempts WHERE id<>a.id AND organization=a.organization AND (target_user=a.target_user OR (issuer=a.issuer AND subject=a.subject));
      UPDATE public.external_login_attempts SET status='consumed',continuation_hash=NULL WHERE id=a.id RETURNING * INTO a;
    ELSIF p_operation IN ('link','register') THEN
      IF a.intent<>'login' THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
      IF a.status NOT IN ('awaiting_account_proof','awaiting_profile') THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('user-sign-in-email:'||a.organization::text,0));
      IF p_operation='link' THEN
        v_user := (p_payload->>'provenUser')::uuid;
        v_target := public.resolve_existing_user_session_v1(v_user);
        IF v_target IS NULL OR (v_target->>'organization')::bigint<>a.organization OR (a.target_user IS NOT NULL AND a.target_user<>v_user) THEN RAISE EXCEPTION 'account_proof_failed'; END IF;
      ELSE
        SELECT (data->>'IS_REGISTRATION_ENABLED')::boolean IS TRUE INTO v_signup FROM public.organizations WHERE id=a.organization FOR SHARE;
        IF v_signup IS DISTINCT FROM true THEN RAISE EXCEPTION 'registration_disabled'; END IF;
        IF NOT a.mailbox_verified THEN RAISE EXCEPTION 'mailbox_proof_required'; END IF;
        IF EXISTS(SELECT 1 FROM public.user_info WHERE organization=a.organization AND lower(btrim(email_readonly))=a.email) THEN
          UPDATE public.external_login_attempts SET status='awaiting_account_proof',continuation_hash=p_payload->>'continuationHash' WHERE id=a.id RETURNING * INTO a;
          RETURN to_jsonb(a)||jsonb_build_object('redirectUri',c.redirect_uri,'origin',c.origin);
        END IF;
        IF EXISTS(SELECT 1 FROM auth.users WHERE email=public.format_auth_email(a.organization,a.email)) THEN RAISE EXCEPTION 'account_identity_inconsistent'; END IF;
        IF coalesce(p_payload#>>'{profile,name}','')='' OR coalesce(p_payload#>>'{profile,surname}','')=''
          OR p_payload->>'consent' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'profile_required'; END IF;
        v_user := public.create_user_in_organization_with_data_pure(a.organization,a.email,p_payload->>'password',p_payload->'profile');
        PERFORM public.initialize_registration_unit_v1(v_user,a.organization,a.email,coalesce(nullif(p_payload->>'unitTitle',''),'Moje akce'));
      END IF;
      SELECT user_id INTO v_existing FROM public.external_login_identities WHERE organization=a.organization AND issuer=a.issuer AND subject=a.subject;
      IF v_existing IS NOT NULL AND v_existing<>v_user THEN RAISE EXCEPTION 'identity_already_linked'; END IF;
      IF EXISTS(SELECT 1 FROM public.external_login_identities WHERE organization=a.organization AND user_id=v_user AND subject<>a.subject) THEN RAISE EXCEPTION 'identity_already_linked'; END IF;
      INSERT INTO public.external_login_identities(organization,user_id,issuer,subject) VALUES(a.organization,v_user,a.issuer,a.subject)
        ON CONFLICT(organization,provider,issuer,subject) DO NOTHING;
      UPDATE public.external_login_attempts SET status='ready',target_user=v_user,continuation_hash=p_payload->>'continuationHash' WHERE id=a.id RETURNING * INTO a;
    ELSIF p_operation='issue' THEN
      IF a.status<>'ready' OR NOT EXISTS(SELECT 1 FROM public.external_login_identities WHERE organization=a.organization AND user_id=a.target_user AND issuer=a.issuer AND subject=a.subject)
        THEN RAISE EXCEPTION 'invalid_provider_proof'; END IF;
      UPDATE public.external_login_attempts SET status='issuing' WHERE id=a.id RETURNING * INTO a;
    ELSIF p_operation='finish' THEN
      IF a.status<>'issuing' OR NOT EXISTS(SELECT 1 FROM public.external_login_identities WHERE organization=a.organization AND user_id=a.target_user AND issuer=a.issuer AND subject=a.subject)
        OR public.resolve_existing_user_session_v1(a.target_user) IS NULL THEN RAISE EXCEPTION 'account_identity_inconsistent'; END IF;
      UPDATE public.external_login_attempts SET status='consumed',continuation_hash=NULL,mailbox_hash=NULL,browser_hash=NULL WHERE id=a.id RETURNING * INTO a;
    ELSE RAISE EXCEPTION 'invalid_operation'; END IF;
  END IF;
  RETURN to_jsonb(a)||jsonb_build_object('redirectUri',c.redirect_uri,'origin',c.origin);
END $$;

CREATE OR REPLACE FUNCTION public.cleanup_external_login_v1()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM public.external_login_attempts WHERE expires_at<clock_timestamp();
  DELETE FROM public.existing_user_session_leases WHERE expires_at<clock_timestamp();
  DELETE FROM public.external_login_rate_limits WHERE window_start<clock_timestamp()-interval '1 hour';
END $$;
REVOKE ALL ON FUNCTION public.google_auth_transition_v1(text,uuid,text,jsonb),public.google_auth_resolve_account_v1(bigint,text),public.google_auth_rate_limit_v1(text,integer),public.cleanup_external_login_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.google_auth_transition_v1(text,uuid,text,jsonb),public.google_auth_resolve_account_v1(bigint,text),public.google_auth_rate_limit_v1(text,integer),public.cleanup_external_login_v1() TO service_role;

CREATE OR REPLACE FUNCTION public.invalidate_external_login_for_user_v1(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM public.external_login_attempts a USING public.user_info u
  WHERE u.id=p_user AND a.organization=u.organization AND
    (a.target_user=u.id OR a.email=lower(btrim(u.email_readonly)) OR EXISTS(
      SELECT 1 FROM public.external_login_identities i WHERE i.user_id=u.id AND i.issuer=a.issuer AND i.subject=a.subject));
  DELETE FROM public.external_login_identities WHERE user_id=p_user;
  DELETE FROM public.existing_user_session_leases WHERE user_id=p_user;
END $$;
REVOKE ALL ON FUNCTION public.invalidate_external_login_for_user_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_external_login_for_user_v1(uuid) TO service_role;


-- Source: database/functions/account_deletion/account_deletion_contract.sql
CREATE OR REPLACE FUNCTION public.create_account_deletion_request(
  p_user uuid,
  p_organization bigint,
  p_token_hash text,
  p_expires_at timestamptz,
  p_masked_email text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_previous public.account_deletion_requests%ROWTYPE;
  v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  IF p_token_hash !~ '^[0-9a-f]{64}$' OR p_expires_at <= clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_invalid_request' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_info ui
    WHERE ui.id = p_user AND ui.organization = p_organization
  ) THEN
    RAISE EXCEPTION 'account_deletion_account_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_previous
  FROM public.account_deletion_requests
  WHERE user_id = p_user
    AND status IN ('email_pending','email_sent','deletion_pending')
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

  IF v_previous.status = 'deletion_pending' THEN
    RAISE EXCEPTION 'account_deletion_already_pending' USING ERRCODE = '55000';
  END IF;
  IF v_previous.id IS NOT NULL AND v_previous.cooldown_until > clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_cooldown' USING ERRCODE = 'P0001';
  END IF;
  IF v_previous.id IS NOT NULL THEN
    UPDATE public.account_deletion_requests
    SET status = 'revoked', token_hash = NULL, masked_email = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_previous.id;
  END IF;

  INSERT INTO public.account_deletion_requests(
    user_id, organization, token_hash, masked_email, expires_at, cooldown_until
  ) VALUES (
    p_user, p_organization, p_token_hash, p_masked_email, p_expires_at,
    clock_timestamp() + interval '5 minutes'
  ) RETURNING * INTO v_request;

  RETURN jsonb_build_object('requestId', v_request.id, 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_account_deletion_email_state(
  p_request_id uuid,
  p_delivered boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_deletion_requests
  SET status = CASE WHEN p_delivered THEN 'email_sent' ELSE 'revoked' END,
      email_sent_at = CASE WHEN p_delivered THEN clock_timestamp() ELSE NULL END,
      token_hash = CASE WHEN p_delivered THEN token_hash ELSE NULL END,
      masked_email = CASE WHEN p_delivered THEN masked_email ELSE NULL END,
      error_class = CASE WHEN p_delivered THEN NULL ELSE 'email_delivery' END,
      updated_at = clock_timestamp()
  WHERE id = p_request_id AND status = 'email_pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.inspect_account_deletion_token(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  IF p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;
  RETURN jsonb_build_object('status', 'valid', 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_account_deletion(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_request public.account_deletion_requests%ROWTYPE;
  v_completion_email text;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1 FOR UPDATE;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status IN ('deletion_pending','failed') AND v_request.used_token_hash = p_token_hash THEN
    RETURN jsonb_build_object('status','processing','requestId',v_request.id,
      'userId',v_request.user_id,'organization',v_request.organization,
      'publicDeleted',v_request.public_deleted,'authDeleted',v_request.auth_deleted,
      'onesignalDeleted',v_request.onesignal_deleted);
  END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;

  v_completion_email := public.get_user_delivery_email(v_request.user_id);

  UPDATE public.account_deletion_requests SET
    status='deletion_pending', used_token_hash=token_hash, token_hash=NULL,
    masked_email=NULL, claimed_at=clock_timestamp(), attempt_count=attempt_count+1,
    updated_at=clock_timestamp()
  WHERE id=v_request.id RETURNING * INTO v_request;
  -- The claim and first-party cleanup share one transaction. Consequently an
  -- already-issued JWT cannot regain domain access between confirmation and a
  -- later Edge call; its public.user_info row is gone before claim commits.
  PERFORM public.cleanup_account_deletion_domain(v_request.id);
  RETURN jsonb_build_object('status','processing','requestId',v_request.id,
    'userId',v_request.user_id,'organization',v_request.organization,
    'completionEmail',v_completion_email,
    'publicDeleted',true,'authDeleted',false,'onesignalDeleted',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_account_deletion_domain(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user uuid; v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE id=p_request_id FOR UPDATE;
  IF v_request.id IS NULL OR v_request.status NOT IN ('deletion_pending','failed') THEN
    RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000';
  END IF;
  IF v_request.public_deleted THEN RETURN jsonb_build_object('status','already_deleted'); END IF;
  v_user := v_request.user_id;

  PERFORM public.record_account_deletion_sync_v1(
    v_user,v_request.organization);

  UPDATE public.cleaning_reports SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.cleaning_reports SET resolved_by=NULL WHERE resolved_by=v_user;
  UPDATE public.news SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.orders_history SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.bank_account_requests SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.transactions SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.client_commits SET actor_id=NULL, actor_display=NULL WHERE actor_id=v_user;
  DELETE FROM public.event_feedback WHERE "user"=v_user;

  DELETE FROM public.client_mutation_receipts WHERE actor_id=v_user;
  DELETE FROM public.client_sync_private_scopes WHERE user_id=v_user;
  DELETE FROM public.activity_assignments WHERE "user"=v_user;
  DELETE FROM public.activity_history WHERE user_id=v_user;
  DELETE FROM public.event_users_saved WHERE "user"=v_user;
  DELETE FROM public.event_users WHERE "user"=v_user;
  DELETE FROM public.user_groups WHERE "user"=v_user;
  DELETE FROM public.user_companions WHERE "user"=v_user OR companion=v_user;
  DELETE FROM public.user_reset_token WHERE "user"=v_user;
  DELETE FROM eshop.bank_account_users WHERE "user"=v_user;
  DELETE FROM public.occasion_users WHERE "user"=v_user;
  DELETE FROM public.unit_users WHERE "user"=v_user;
  DELETE FROM public.organization_users WHERE "user"=v_user;
  PERFORM public.invalidate_external_login_for_user_v1(v_user);
  DELETE FROM public.user_info WHERE id=v_user;

  UPDATE public.account_deletion_requests SET public_deleted=true,
    status='deletion_pending', error_class=NULL, updated_at=clock_timestamp()
  WHERE id=p_request_id;
  RETURN jsonb_build_object('status','deleted');
END;
$$;

CREATE OR REPLACE FUNCTION public.get_account_deletion_storage_batch(
  p_request_id uuid,
  p_limit integer DEFAULT 100
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user uuid; v_result jsonb;
BEGIN
  PERFORM public.require_service_role();
  IF p_limit < 1 OR p_limit > 1000 THEN
    RAISE EXCEPTION 'account_deletion_invalid_storage_batch_limit' USING ERRCODE = '22023';
  END IF;
  SELECT user_id INTO v_user
  FROM public.account_deletion_requests
  WHERE id=p_request_id AND status IN ('deletion_pending','failed');
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'bucketId', item.bucket_id, 'name', item.name
  ) ORDER BY item.bucket_id,item.name),'[]'::jsonb)
  INTO v_result
  FROM (
    SELECT bucket_id,name FROM storage.objects
    WHERE owner_id=v_user::text
    ORDER BY bucket_id,name LIMIT p_limit
  ) item;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_account_deletion_job(
  p_request_id uuid,
  p_auth_deleted boolean DEFAULT NULL,
  p_onesignal_deleted boolean DEFAULT NULL,
  p_error_class text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_deletion_requests SET
    auth_deleted=coalesce(p_auth_deleted,auth_deleted),
    onesignal_deleted=coalesce(p_onesignal_deleted,onesignal_deleted),
    error_class=p_error_class,
    status=CASE
      WHEN public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN 'completed'
      WHEN p_error_class IS NOT NULL THEN 'failed' ELSE 'deletion_pending' END,
    completed_at=CASE
      WHEN public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN clock_timestamp()
      ELSE completed_at END,
    user_id=CASE
      WHEN public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN NULL ELSE user_id END,
    updated_at=clock_timestamp()
  WHERE id=p_request_id AND status IN ('deletion_pending','failed')
  RETURNING * INTO v_request;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
  RETURN jsonb_build_object('status',v_request.status);
END;
$$;

REVOKE ALL ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_account_deletion(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_account_deletion_domain(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_account_deletion_storage_batch(uuid,integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_account_deletion(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_account_deletion_domain(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_storage_batch(uuid,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) TO service_role;
REVOKE ALL ON FUNCTION public.inspect_account_deletion_token(text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.inspect_account_deletion_token(text) TO anon, service_role;

DO $$ BEGIN
  IF current_database() = current_setting('cron.database_name', true)
     AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('festapp-external-login-cleanup-v1','0 * * * *',
      $job$SELECT public.cleanup_external_login_v1();$job$);
  END IF;
  -- Canonical self-hosted targets use pg_cron in the control-plane postgres DB.
  -- install-google-auth-cleanup.sh installs only this job in that scheduler
  -- before tenant rows are enabled; rehearsal cron stubs must not be called.
END $$;
