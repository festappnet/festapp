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
