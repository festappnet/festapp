DO $guard$
BEGIN
  IF to_regprocedure('public.get_app_config_v203(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'required legacy get_app_config_v203(jsonb) is missing';
  END IF;
  IF to_regprocedure('public.get_app_config_v218(jsonb)') IS NOT NULL
    OR to_regprocedure('public.get_app_config_v219(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'app-config compatibility alias already exists';
  END IF;
END
$guard$;

CREATE FUNCTION public.get_app_config_v218(data_in jsonb)
RETURNS jsonb
LANGUAGE sql
AS $function$
  SELECT public.get_app_config_v203(data_in)
$function$;

CREATE FUNCTION public.get_app_config_v219(data_in jsonb)
RETURNS jsonb
LANGUAGE sql
AS $function$
  SELECT public.get_app_config_v203(data_in)
$function$;

REVOKE ALL ON FUNCTION public.get_app_config_v218(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_app_config_v219(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_app_config_v218(jsonb)
  TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_app_config_v219(jsonb)
  TO anon,authenticated,service_role;

COMMENT ON FUNCTION public.get_app_config_v218(jsonb) IS
  'Slunovrat legacy compatibility alias to get_app_config_v203.';
COMMENT ON FUNCTION public.get_app_config_v219(jsonb) IS
  'Slunovrat legacy compatibility alias to get_app_config_v203.';
