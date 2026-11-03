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
