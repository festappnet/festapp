-- Restore the canonical legacy artwork fence on targets retaining the older general-settings adapter.
-- Exact authored owner: database/functions/others/legacy_occasion_facades.sql.
BEGIN;
CREATE OR REPLACE FUNCTION public.update_occasion_203(input_data jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.save_occasion_legacy_facade_internal_v1(input_data);
 IF result->>'status'='conflict' THEN RAISE serialization_failure USING MESSAGE='occasion changed'; END IF;
 IF result->>'status'='rejected' THEN RAISE invalid_parameter_value USING MESSAGE='occasion save rejected'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.update_occasion_203(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_occasion_203(jsonb) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
