\set ON_ERROR_STOP on
-- Apply only after explicit authorization of the shared database impact.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('festapp-data-security-20261018',0));
DO $$
BEGIN
 IF current_database()<>'festapp_rehearsal_20260909220601'
 OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=1) THEN
   RAISE EXCEPTION 'Canonical target mismatch';
 END IF;

 IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261018100000') THEN
   RAISE EXCEPTION 'Already recorded; read back rather than replay';
 END IF;
END $$;
-- Canonical sources: database/functions/users/create_user_from_registration.sql, database/functions/users/create_user_in_organization_with_data_ws.sql, database/functions/security/data_security_auth.sql

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

    -- Public registration policy is independent of any caller's manager roles.
    IF is_registration_enabled IS DISTINCT FROM true THEN
        RETURN jsonb_build_object('code', 403, 'error', 'Registration is disabled for this organization');
    END IF;

    -- Call the PURE function to create the user
    new_user_id := create_user_in_organization_with_data_pure(org, email, password, data);

    PERFORM public.initialize_registration_unit_v1(new_user_id, org, email, unit_title);

    RETURN jsonb_build_object('code', 200, 'id', new_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_user_from_registration(bigint,text,text,jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_user_from_registration(bigint,text,text,jsonb,text) TO service_role;

CREATE OR REPLACE FUNCTION create_user_in_organization_with_data_ws(org bigint, email text, password text, data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Internal helper. The scoped parent (update_user_internal_v1) owns admission.
    -- No client EXECUTE: public registration has its own atomic email owner.
    -- Call the PURE function
    new_user_id := create_user_in_organization_with_data_pure(org, email, password, data);

    -- Return success in JSON format
    RETURN jsonb_build_object('code', 200, 'id', new_user_id);
END;
$$;
REVOKE ALL ON FUNCTION public.create_user_in_organization_with_data_ws(bigint,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Retire superseded Auth writers. No CASCADE: unexpected dependencies abort.
DROP FUNCTION IF EXISTS public.set_user_password(uuid,bigint,text);
DROP FUNCTION IF EXISTS public.create_user_in_organization_with_data(bigint,text,text,jsonb);
DROP FUNCTION IF EXISTS public.create_user(bigint,text,text);
DROP FUNCTION IF EXISTS public.create_user_with_data(bigint,text,text,jsonb);
-- Pure invokers remain internal; callers cannot acquire Auth INSERT rights.
REVOKE ALL ON FUNCTION public.create_user_in_organization_with_data_pure(bigint,text,text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_user_in_organization_with_data_pure(bigint,text,text,text,jsonb) FROM PUBLIC,anon,authenticated;

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('set_user_password','create_user','create_user_with_data','create_user_in_organization_with_data')) THEN
 RAISE EXCEPTION 'Unexpected legacy Auth overload; review before containment'; END IF;
END $$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
 VALUES('20261018100000','data_security_auth',ARRAY['-- sha256:f2f3db992e95ade63c46543b8324e2a9f6a3f123734d19bffe9e1e77ad6686e3']);
NOTIFY pgrst,'reload schema';
COMMIT;
